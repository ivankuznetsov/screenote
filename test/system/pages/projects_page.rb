# frozen_string_literal: true

module Pages
  module ProjectsPage
    # --- Selectors ---

    PAGE_TITLE = '[data-testid="page-title"]'
    PROJECT_CARD = '[data-testid="project-card"]'
    PROJECT_CARD_NAME = '[data-testid="project-card-name"]'
    FORM = '[data-testid="project-form"]'
    FORM_ERRORS = '[data-testid="project-form-errors"]'
    PROJECT_DETAIL_TITLE = '[data-testid="project-detail-title"]'
    PROJECT_DETAIL_DESCRIPTION = '[data-testid="project-detail-description"]'
    EMPTY_STATE = '[data-testid="empty-state"]'

    # --- Actions ---

    def visit_projects
      visit "/projects"
      assert_selector "#{PAGE_TITLE}, [data-testid='empty-state']", wait: 10
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

    def navigate_to_demo_project
      visit_projects
      click_project("Demo Project")
      assert_on_project_show("Demo Project")
    end

    # --- Assertions ---

    def assert_on_projects_index
      assert_selector PAGE_TITLE, text: "Projects", wait: 10
    end

    def assert_project_not_visible(name)
      assert_no_selector PROJECT_CARD_NAME, text: name, wait: 5
    end

    def assert_on_project_show(name)
      assert_selector PROJECT_DETAIL_TITLE, text: name, wait: 10
    end

    def assert_form_error
      assert_selector FORM_ERRORS, wait: 5
    end
  end
end
