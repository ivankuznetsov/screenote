# frozen_string_literal: true

require_relative "application_system_test_case"
require_relative "pages/auth_page"
require_relative "pages/projects_page"

class ProjectsTest < ApplicationSystemTestCase
  include Pages::AuthPage
  include Pages::ProjectsPage

  setup do
    login_as_test_user
  end

  test "projects index shows existing projects" do
    visit_projects

    assert_on_projects_index
    assert_selector PROJECT_CARD, minimum: 1
  end

  test "create a new project" do
    project_name = "E2E Test Project #{Time.now.to_i}"

    visit_new_project
    fill_project_form(name: project_name, description: "Created by e2e test")
    submit_project_form

    assert_flash_notice "Project created."
    assert_on_project_show(project_name)
    assert_selector PROJECT_DETAIL_DESCRIPTION, text: "Created by e2e test"
  end

  test "create project without name shows validation error" do
    visit_new_project
    fill_project_form(name: "", description: "Missing name")
    submit_project_form

    assert_form_error
  end

  test "edit a project" do
    project_name = "Edit Test #{Time.now.to_i}"

    # Create project first
    visit_new_project
    fill_project_form(name: project_name, description: "Original description")
    submit_project_form
    assert_on_project_show(project_name)

    # Edit
    click_link "Edit"
    assert_selector PAGE_TITLE, text: "Edit project", wait: 10

    updated_name = "Updated #{project_name}"
    fill_project_form(name: updated_name, description: "Updated description")
    submit_project_form

    assert_flash_notice "Project updated."
    assert_on_project_show(updated_name)
  end

  test "delete a project" do
    project_name = "Delete Test #{Time.now.to_i}"

    # Create project first
    visit_new_project
    fill_project_form(name: project_name, description: "Will be deleted")
    submit_project_form
    assert_on_project_show(project_name)

    # Delete
    accept_confirm do
      click_button "Delete"
    end

    assert_flash_notice "Project deleted."
    assert_on_projects_index
    assert_project_not_visible(project_name)
  end

  test "navigate to project from index" do
    visit_projects

    # Click the first project card
    project_name = find(PROJECT_CARD_NAME, match: :first).text
    click_project(project_name)

    assert_on_project_show(project_name)
  end

  test "new project button on index page" do
    visit_projects

    click_link "New project"

    assert_selector PAGE_TITLE, text: "New project", wait: 10
    assert_selector FORM
  end

  test "cancel new project returns to index" do
    visit_new_project

    click_link "Cancel"

    assert_on_projects_index
  end
end
