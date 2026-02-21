# frozen_string_literal: true

require_relative "application_system_test_case"
require_relative "pages/auth_page"
require_relative "pages/projects_page"
require_relative "pages/pages_page"
require_relative "pages/screenshots_page"

class ScreenshotsTest < ApplicationSystemTestCase
  include Pages::AuthPage
  include Pages::ProjectsPage
  include Pages::PagesPage
  include Pages::ScreenshotsPage

  setup do
    login_as_test_user
  end

  test "upload a screenshot to a page" do
    navigate_to_demo_page

    click_link "Upload version"
    assert_selector PAGE_TITLE, text: "Upload version", wait: 10

    screenshot_title = "E2E Screenshot #{Time.now.to_i}"
    fill_screenshot_form(title: screenshot_title, image_path: TEST_IMAGE_PATH)
    submit_screenshot_form

    assert_flash_notice "Screenshot uploaded."
    assert_on_screenshot_show
    assert_screenshot_title_in_breadcrumb(screenshot_title)
  end

  test "screenshot show page displays image and sidebar" do
    create_screenshot("Show Test #{Time.now.to_i}")

    assert_on_screenshot_show
    assert_screenshot_image_loaded
    assert_selector ANNOTATION_SIDEBAR, wait: 10
    assert_selector SIDEBAR_TITLE, text: "Annotations"
    assert_annotation_sidebar_empty
  end

  test "edit a screenshot title" do
    original_title = "Original Title #{Time.now.to_i}"
    create_screenshot(original_title)

    click_link "Edit"
    assert_selector PAGE_TITLE, text: "Edit version", wait: 10

    updated_title = "Updated Title #{Time.now.to_i}"
    fill_in "screenshot[title]", with: updated_title
    submit_screenshot_form

    assert_flash_notice "Screenshot updated."
    assert_screenshot_title_in_breadcrumb(updated_title)
  end

  test "delete a screenshot" do
    create_screenshot("Delete Me #{Time.now.to_i}")

    accept_confirm do
      click_button "Delete"
    end

    assert_flash_notice "Screenshot deleted."
    assert_on_page_show
  end

  test "upload screenshot without title shows validation error" do
    navigate_to_demo_page

    click_link "Upload version"

    fill_screenshot_form(title: "", image_path: TEST_IMAGE_PATH)
    submit_screenshot_form

    assert_screenshot_form_error
  end

  test "screenshot appears in page version grid" do
    screenshot_title = "Grid Test #{Time.now.to_i}"
    create_screenshot(screenshot_title)

    # Navigate back to page via breadcrumb
    within find(BREADCRUMB) do
      all("a").last.click
    end
    wait_for_turbo

    assert_selector SCREENSHOT_CARD_TITLE, text: screenshot_title, wait: 10
  end

  test "screenshot breadcrumb shows project, page, and version" do
    create_screenshot("Breadcrumb Test #{Time.now.to_i}")

    breadcrumb = find(BREADCRUMB)
    assert breadcrumb.has_text?("Demo Project"), "Breadcrumb should include project name"
    assert breadcrumb.has_text?("Breadcrumb Test"), "Breadcrumb should include screenshot title"
  end

  private

  def navigate_to_demo_page
    navigate_to_demo_project
    navigate_to_first_page
  end

  def create_screenshot(title)
    navigate_to_demo_page
    click_link "Upload version"
    fill_screenshot_form(title: title, image_path: TEST_IMAGE_PATH)
    submit_screenshot_form
    assert_on_screenshot_show
  end
end
