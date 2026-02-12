# frozen_string_literal: true

require "test_helper"
require "capybara-playwright-driver"

# System tests run against the dev server on port 3005 (must be running: bin/dev).
# Uses Capybara with the Playwright driver for real browser automation.
#
# API guidelines:
#   - Prefer Capybara methods (find, assert_selector, fill_in, click_button) for most interactions.
#   - Use with_playwright_page for hover, response interception, or low-level mouse/keyboard.
Capybara.run_server = false
Capybara.app_host = ENV.fetch("APP_HOST", "http://localhost:3005")
Capybara.default_max_wait_time = 15
Capybara.save_path = "tmp/capybara"

class ApplicationSystemTestCase < ActionDispatch::SystemTestCase
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
    assert_selector ".rsa-auth-form", wait: 10
  end

  # --- Turbo helpers ---

  def wait_for_turbo
    has_no_css?(".turbo-progress-bar", wait: 10)
  end

  # --- Playwright helpers ---

  def with_playwright_page(&block)
    page.driver.with_playwright_page(&block)
  end
end
