# frozen_string_literal: true

module Pages
  module ScreenshotsPage
    # --- Selectors ---

    BREADCRUMB = '[data-testid="breadcrumb"]'
    SCREENSHOT_WORKSPACE = '[data-testid="screenshot-workspace"]'
    SCREENSHOT_IMAGE = '[data-testid="screenshot-image"]'
    ANNOTATION_SIDEBAR = '[data-testid="annotation-sidebar"]'
    SIDEBAR_TITLE = '[data-testid="sidebar-title"]'
    SIDEBAR_EMPTY = '[data-testid="sidebar-empty"]'

    # --- Actions ---

    def fill_screenshot_form(title:, image_path: nil)
      fill_in "screenshot[title]", with: title
      attach_file "screenshot[image]", image_path if image_path
    end

    def submit_screenshot_form
      find('input[type="submit"]').click
    end

    # --- Assertions ---

    def assert_on_screenshot_show
      assert_selector SCREENSHOT_WORKSPACE, wait: 10
    end

    def assert_screenshot_title_in_breadcrumb(title)
      assert_selector BREADCRUMB, text: title, wait: 10
    end

    def assert_annotation_sidebar_empty
      assert_selector SIDEBAR_EMPTY, wait: 10
    end

    def assert_screenshot_image_loaded
      assert_selector SCREENSHOT_IMAGE, wait: 10
    end
  end
end
