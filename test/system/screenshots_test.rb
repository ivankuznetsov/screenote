# frozen_string_literal: true

require_relative "application_system_test_case"
require_relative "pages/auth_page"
require_relative "pages/projects_page"
require_relative "pages/screenshots_page"

class ScreenshotsTest < ApplicationSystemTestCase
  include Pages::AuthPage
  include Pages::ProjectsPage
  include Pages::ScreenshotsPage

  setup do
    login_as_test_user
  end

  test "upload a screenshot to a project" do
    # Navigate to the seed project
    visit_projects
    click_project("Demo Project")
    assert_on_project_show("Demo Project")

    # Upload screenshot
    click_link "Upload screenshot"
    assert_selector PAGE_TITLE, text: "Upload screenshot", wait: 10

    screenshot_title = "E2E Screenshot #{Time.now.to_i}"
    image_path = Rails.root.join("test/fixtures/files/test_image.png").to_s

    fill_screenshot_form(title: screenshot_title, image_path: image_path)
    submit_screenshot_form

    assert_flash_notice "Screenshot uploaded."
    assert_on_screenshot_show
    assert_screenshot_title_in_breadcrumb(screenshot_title)
  end

  test "screenshot show page displays image and sidebar" do
    # Create a screenshot first
    visit_projects
    click_project("Demo Project")
    click_link "Upload screenshot"

    screenshot_title = "Show Test #{Time.now.to_i}"
    image_path = Rails.root.join("test/fixtures/files/test_image.png").to_s
    fill_screenshot_form(title: screenshot_title, image_path: image_path)
    submit_screenshot_form

    assert_on_screenshot_show
    assert_screenshot_image_loaded
    assert_selector ANNOTATION_SIDEBAR, wait: 10
    assert_selector SIDEBAR_TITLE, text: "Annotations"
    assert_annotation_sidebar_empty
  end

  test "edit a screenshot title" do
    # Create a screenshot
    visit_projects
    click_project("Demo Project")
    click_link "Upload screenshot"

    original_title = "Original Title #{Time.now.to_i}"
    image_path = Rails.root.join("test/fixtures/files/test_image.png").to_s
    fill_screenshot_form(title: original_title, image_path: image_path)
    submit_screenshot_form
    assert_on_screenshot_show

    # Edit
    click_link "Edit"
    assert_selector PAGE_TITLE, text: "Edit screenshot", wait: 10

    updated_title = "Updated Title #{Time.now.to_i}"
    fill_in "screenshot[title]", with: updated_title
    submit_screenshot_form

    assert_flash_notice "Screenshot updated."
    assert_screenshot_title_in_breadcrumb(updated_title)
  end

  test "delete a screenshot" do
    # Create a screenshot
    visit_projects
    click_project("Demo Project")
    click_link "Upload screenshot"

    screenshot_title = "Delete Me #{Time.now.to_i}"
    image_path = Rails.root.join("test/fixtures/files/test_image.png").to_s
    fill_screenshot_form(title: screenshot_title, image_path: image_path)
    submit_screenshot_form
    assert_on_screenshot_show

    # Delete
    accept_confirm do
      click_button "Delete"
    end

    assert_flash_notice "Screenshot deleted."
    # Should redirect back to the project or screenshots index
    assert_selector PAGE_TITLE, wait: 10
  end

  test "upload screenshot without title shows validation error" do
    visit_projects
    click_project("Demo Project")
    click_link "Upload screenshot"

    image_path = Rails.root.join("test/fixtures/files/test_image.png").to_s
    fill_screenshot_form(title: "", image_path: image_path)
    submit_screenshot_form

    assert_selector ".form__errors", wait: 5
  end

  test "screenshot appears in project screenshot grid" do
    screenshot_title = "Grid Test #{Time.now.to_i}"

    visit_projects
    click_project("Demo Project")
    click_link "Upload screenshot"

    image_path = Rails.root.join("test/fixtures/files/test_image.png").to_s
    fill_screenshot_form(title: screenshot_title, image_path: image_path)
    submit_screenshot_form
    assert_on_screenshot_show

    # Go back to project
    find(BREADCRUMB).find("a", match: :first).click
    wait_for_turbo

    assert_selector SCREENSHOT_CARD_TITLE, text: screenshot_title, wait: 10
  end
end
