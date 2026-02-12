# frozen_string_literal: true

module Pages
  module ScreenshotsPage
    # --- Selectors ---

    PAGE_TITLE = ".page-header__title"
    FORM = ".form"
    TITLE_FIELD = 'input[name="screenshot[title]"]'
    IMAGE_FIELD = 'input[name="screenshot[image]"]'

    # Screenshot show
    SCREENSHOT_HEADER = ".screenshot-header"
    BREADCRUMB = ".screenshot-header__breadcrumb"
    SCREENSHOT_WORKSPACE = ".screenshot-workspace"
    SCREENSHOT_IMAGE = ".screenshot-canvas__image"
    EDIT_BUTTON = ".screenshot-header__actions .btn--secondary"
    DELETE_BUTTON = ".screenshot-header__actions .btn--danger"

    # Sidebar
    ANNOTATION_SIDEBAR = ".annotation-sidebar"
    SIDEBAR_TITLE = ".annotation-sidebar__title"
    SIDEBAR_EMPTY = ".annotation-sidebar__empty"
    ANNOTATION_FILTER = ".annotation-filter"
    ANNOTATION_FILTER_ACTIVE = ".annotation-filter--active"

    # --- Actions ---

    def visit_new_screenshot(project_id)
      visit "/projects/#{project_id}/screenshots/new"
      assert_selector FORM, wait: 10
    end

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
