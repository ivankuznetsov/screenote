# frozen_string_literal: true

require "test_helper"
require "capybara-playwright-driver"
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

  driven_by :playwright, screen_size: [ 1280, 720 ], options: {
    browser_type: ENV.fetch("PLAYWRIGHT_BROWSER", "chromium").to_sym,
    headless: ENV["HEADED"] != "true"
  }

  teardown do
    take_screenshot unless passed?
  end

  private

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
    visit uri.request_uri
  end
end
