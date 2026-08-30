# frozen_string_literal: true

require "test_helper"
require "capybara-playwright-driver"
require "fileutils"
require "json"
require "uri"

# System tests run against the dev server on port 3005 (must be running: bin/dev).
# Uses Capybara with the Playwright driver for real browser automation.
#
# API guidelines:
#   - Prefer Capybara methods (find, assert_selector, fill_in, click_button) for most interactions.
#   - Use with_playwright_page for hover, response interception, or low-level mouse/keyboard.
if ENV["CAPYBARA_RUN_SERVER"] == "true"
  Capybara.run_server = true
else
  Capybara.run_server = false
  Capybara.app_host = ENV.fetch("APP_HOST", "http://localhost:3005")
end
Capybara.default_max_wait_time = 15
Capybara.save_path = "tmp/capybara"

class ApplicationSystemTestCase < ActionDispatch::SystemTestCase
  TEST_IMAGE_PATH = Rails.root.join("test/fixtures/files/test_image.png").to_s
  # A realistically sized page capture. Geometry claims about the annotation
  # overlay only mean something against a screenshot the size of a real one.
  DESKTOP_SCREENSHOT_PATH = Rails.root.join("test/fixtures/files/desktop_screenshot.png").to_s
  # Set SCREENOTE_EVIDENCE_DIR to have a run write named frames, the page facts
  # behind each frame, and a per-test trace into that directory. The trace
  # carries the screencast `script/attachment_browser_evidence` encodes into a
  # video. Nothing is recorded otherwise, so an ordinary run pays nothing for it.
  EVIDENCE_DIR = ENV["SCREENOTE_EVIDENCE_DIR"].presence
  # The width every desktop layout claim is measured at, and the width a test
  # returns to after narrowing the viewport.
  SCREEN_SIZE = [ 1280, 720 ].freeze

  driven_by :playwright, screen_size: SCREEN_SIZE, options: {
    browser_type: ENV.fetch("PLAYWRIGHT_BROWSER", "chromium").to_sym,
    headless: ENV["HEADED"] != "true",
    deviceScaleFactor: Float(ENV.fetch("DEVICE_SCALE_FACTOR", "1"))
  }

  setup do
    start_evidence_trace
    # The test environment's NullStore intentionally makes fail-closed rate
    # limiters unavailable. Give each system test a functional isolated store
    # so in-process browser/API requests exercise limits without sharing state.
    @original_system_test_cache = Rails.cache
    @original_system_controller_cache_store = ActionController::Base.cache_store
    isolated_store = ActiveSupport::Cache::MemoryStore.new
    Rails.cache = isolated_store
    ActionController::Base.cache_store = isolated_store
  end

  teardown do
    take_screenshot unless passed?
  ensure
    ActionController::Base.cache_store = @original_system_controller_cache_store
    Rails.cache = @original_system_test_cache
  end

  # Capybara resets the session in `after_teardown`, which closes the browser
  # context and takes the recording with it. Anything read from the live browser
  # has to happen here, which is the same reason Rails saves its failure
  # screenshot from `before_teardown`.
  def before_teardown
    save_evidence_trace
  ensure
    super
  end

  private

  # --- Evidence helpers ---

  def evidence_capture?
    EVIDENCE_DIR.present?
  end

  def evidence_directory
    @evidence_directory ||= Pathname.new(EVIDENCE_DIR).tap { |dir| FileUtils.mkdir_p(dir) }
  end

  # Records the run itself, not just its outcome: a Playwright trace carries a
  # timestamped screencast and a DOM snapshot per action, so the whole authoring
  # flow can be replayed with `npx playwright show-trace <file>` and encoded
  # into a watchable video from the screencast alone.
  #
  # Playwright's own `record_video_dir` is deliberately not set. `reset!` in this
  # driver asks the page for its video path while the page is still open, and
  # `Playwright::Video#path` blocks on a future that the page-close event
  # rejects, so a run that sets the option hangs and leaves a zero-byte file.
  def start_evidence_trace
    @evidence_frame_number = 0
    return unless evidence_capture?

    page.driver.start_tracing(name: name, screenshots: true, snapshots: true)
  rescue StandardError => error
    puts "[evidence] could not start the trace for #{name}: #{error.message}"
  end

  def save_evidence_trace
    return unless evidence_capture?

    page.driver.stop_tracing(path: evidence_directory.join("#{name.parameterize}.trace.zip").to_s)
  rescue StandardError => error
    # Evidence collection must never decide whether a test passed.
    puts "[evidence] could not save the trace for #{name}: #{error.message}"
  end

  # Writes one named frame plus the page facts behind it. A screenshot alone
  # cannot show which URL an image was fetched from or which component context
  # rendered it, so the reviewable claim lives beside the picture.
  def capture_evidence(label, facts: {})
    return unless evidence_capture?

    @evidence_frame_number += 1
    slug = format("%02d-%s-%s", @evidence_frame_number, name.parameterize, label.parameterize)
    with_playwright_page { |pw_page| pw_page.screenshot(path: evidence_directory.join("#{slug}.png").to_s) }
    evidence_directory.join("#{slug}.json").write(JSON.pretty_generate(
      { test: name, label: label, viewport: evidence_viewport }.merge(facts)
    ))
  end

  def evidence_viewport
    with_playwright_page do |pw_page|
      pw_page.evaluate("({ width: window.innerWidth, height: window.innerHeight })")
    end
  end

  # --- Auth helpers ---

  def login_as(email, password)
    visit "/session/new"
    fill_in "email", with: email
    fill_in "password", with: password
    click_button "Sign In"
    assert_selector '[data-testid="page-title"], [data-testid="empty-state"], [data-testid="project-list"]', wait: 10
  end

  def login_as_test_user
    login_as("test@screenote.app", "password")
  end

  def logout
    click_button "Sign out"
    assert_no_selector '[data-testid="sign-out-button"]', wait: 10
  end

  # --- Turbo helpers ---

  def wait_for_turbo
    assert_no_selector ".turbo-progress-bar", wait: 10
  end

  # --- Flash helpers ---

  FLASH_NOTICE = '[data-testid="flash-notice"]'

  def assert_flash_notice(text)
    assert_selector FLASH_NOTICE, text: text, wait: 10
  end

  # --- Playwright helpers ---

  def with_playwright_page(&block)
    page.driver.with_playwright_page(&block)
  end

  def app_base_url
    return Capybara.app_host if Capybara.app_host.present?

    current_uri = URI.parse(page.current_url)
    "#{current_uri.scheme}://#{current_uri.host}:#{current_uri.port}"
  end

  def visit_app_url(url)
    uri = URI.parse(url)
    destination = uri.request_uri
    destination = "#{destination}##{uri.fragment}" if uri.fragment
    visit destination
  end
end
