# frozen_string_literal: true

module Pages
  module ScreenshotsPage
    # --- Selectors ---

    SCREENSHOT_FORM = '[data-testid="screenshot-form"]'
    SCREENSHOT_FORM_ERRORS = '[data-testid="screenshot-form-errors"]'
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

    def assert_screenshot_form_error
      assert_selector SCREENSHOT_FORM_ERRORS, wait: 5
    end

    def assert_screenshot_image_loaded
      assert_selector SCREENSHOT_IMAGE, wait: 10
      # Verify image pixels are fully loaded, not just DOM element.
      # Annotorious and coordinate calculations depend on actual pixel dimensions.
      script = "(() => { const img = document.querySelector('[data-testid=\"screenshot-image\"]'); " \
               "return img && img.complete && img.naturalWidth > 0 })()"
      10.times do
        break if page.evaluate_script(script)
        sleep 0.5
      end
      assert page.evaluate_script(script), "Screenshot image failed to load - naturalWidth is 0"
    end
  end
end
