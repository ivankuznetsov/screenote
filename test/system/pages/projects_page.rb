# frozen_string_literal: true

module Pages
  module ProjectsPage
    # --- Selectors ---

    PAGE_HEADER = ".page-header"
    PAGE_TITLE = ".page-header__title"
    NEW_PROJECT_BUTTON = 'a.btn.btn--primary[href="/projects/new"]'
    PROJECT_LIST = ".project-list"
    PROJECT_CARD = ".project-card"
    PROJECT_CARD_NAME = ".project-card__name"
    PROJECT_CARD_DESCRIPTION = ".project-card__description"
    EMPTY_STATE = ".empty-state"
    EMPTY_STATE_TITLE = ".empty-state__title"

    # Project form
    FORM = ".form"
    NAME_FIELD = 'input[name="project[name]"]'
    DESCRIPTION_FIELD = 'textarea[name="project[description]"]'
    FORM_ERRORS = ".form__errors"

    # Project detail
    PROJECT_DETAIL_TITLE = ".project-detail__title"
    PROJECT_DETAIL_DESCRIPTION = ".project-detail__description"
    PROJECT_DETAIL_ACTIONS = ".project-detail__actions"
    UPLOAD_SCREENSHOT_BUTTON = ".project-detail__actions .btn--primary"
    EDIT_PROJECT_BUTTON = "a.btn.btn--secondary"
    DELETE_PROJECT_BUTTON = ".project-detail__actions .btn--danger"

    # Screenshot grid on project show
    SCREENSHOT_GRID = ".screenshot-grid"
    SCREENSHOT_CARD = ".screenshot-card"
    SCREENSHOT_CARD_TITLE = ".screenshot-card__title"

    # --- Actions ---

    def visit_projects
      visit "/projects"
      assert_selector "body", wait: 10
    end

    def visit_new_project
      visit "/projects/new"
      assert_selector FORM, wait: 10
    end

    def fill_project_form(name:, description: "")
      fill_in "project[name]", with: name
      fill_in "project[description]", with: description
    end

    def submit_project_form
      find('input[type="submit"]').click
    end

    def click_project(name)
      find(PROJECT_CARD_NAME, text: name).click
    end

    # --- Assertions ---

    def assert_on_projects_index
      assert_selector PAGE_TITLE, text: "Projects", wait: 10
    end

    def assert_project_visible(name)
      assert_selector PROJECT_CARD_NAME, text: name, wait: 10
    end

    def assert_project_not_visible(name)
      assert_no_selector PROJECT_CARD_NAME, text: name, wait: 5
    end

    def assert_on_project_show(name)
      assert_selector PROJECT_DETAIL_TITLE, text: name, wait: 10
    end

    def assert_empty_projects
      assert_selector EMPTY_STATE_TITLE, text: "No projects yet", wait: 10
    end

    def assert_form_error
      assert_selector FORM_ERRORS, wait: 5
    end
  end
end
