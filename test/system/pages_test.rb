# frozen_string_literal: true

require_relative "application_system_test_case"
require_relative "pages/auth_page"
require_relative "pages/projects_page"
require_relative "pages/pages_page"
require_relative "pages/screenshots_page"

class PagesTest < ApplicationSystemTestCase
  include Pages::AuthPage
  include Pages::ProjectsPage
  include Pages::PagesPage
  include Pages::ScreenshotsPage

  setup do
    login_as_test_user
  end

  test "project show displays page cards" do
    navigate_to_demo_project

    assert_selector PAGE_CARD, minimum: 1, wait: 10
  end

  test "create a new page from project show" do
    navigate_to_demo_project

    page_name = "E2E Page #{Time.now.to_i}"
    click_new_page
    fill_page_form(name: page_name)
    submit_page_form

    assert_flash_notice "Page created."
    assert_on_page_show(page_name)
  end

  test "create page without name shows validation error" do
    navigate_to_demo_project

    click_new_page
    fill_page_form(name: "")
    submit_page_form

    assert_page_form_error
  end

  test "edit a page name" do
    navigate_to_demo_project

    page_name = "Edit Page #{Time.now.to_i}"
    click_new_page
    fill_page_form(name: page_name)
    submit_page_form
    assert_on_page_show(page_name)

    click_link "Edit"
    assert_selector PAGE_TITLE, text: "Edit page", wait: 10

    updated_name = "Updated #{page_name}"
    fill_page_form(name: updated_name)
    submit_page_form

    assert_flash_notice "Page updated."
    assert_on_page_show(updated_name)
  end

  test "delete a page" do
    navigate_to_demo_project

    page_name = "Delete Page #{Time.now.to_i}"
    click_new_page
    fill_page_form(name: page_name)
    submit_page_form
    assert_on_page_show(page_name)

    accept_confirm do
      find(DELETE_PAGE_BUTTON).click
    end

    assert_flash_notice "Page deleted."
    assert_on_project_show("Demo Project")
    assert_page_card_not_visible(page_name)
  end

  test "navigate from project to page and back" do
    navigate_to_demo_project

    # Click into first page
    page_name = find(PAGE_CARD_NAME, match: :first).text
    click_page(page_name)
    assert_on_page_show(page_name)

    # Navigate back via breadcrumb
    within '[data-testid="breadcrumb"]' do
      click_link "Demo Project"
    end
    wait_for_turbo

    assert_on_project_show("Demo Project")
  end

  test "cancel new page returns to project show" do
    navigate_to_demo_project

    click_new_page
    click_link "Cancel"

    assert_on_project_show("Demo Project")
  end

  test "page show displays empty state when no versions" do
    navigate_to_demo_project

    page_name = "Empty Page #{Time.now.to_i}"
    click_new_page
    fill_page_form(name: page_name)
    submit_page_form
    assert_on_page_show(page_name)

    assert_selector EMPTY_STATE, text: "No versions yet", wait: 10
  end

  test "page shows version count on project show" do
    navigate_to_demo_project

    # The seed "Test Screenshot" page should show at least 1 version
    assert_selector PAGE_CARD, minimum: 1
    first_card = find(PAGE_CARD, match: :first)
    assert first_card.has_text?(/\d+ versions?/), "Page card should show version count"
  end

  test "duplicate page name shows validation error" do
    navigate_to_demo_project

    page_name = "Duplicate Page #{Time.now.to_i}"
    click_new_page
    fill_page_form(name: page_name)
    submit_page_form
    assert_on_page_show(page_name)

    # Go back and create another with the same name
    within '[data-testid="breadcrumb"]' do
      click_link "Demo Project"
    end
    wait_for_turbo

    click_new_page
    fill_page_form(name: page_name)
    submit_page_form

    assert_page_form_error
  end

  test "page card shows placeholder when no screenshots uploaded" do
    navigate_to_demo_project

    page_name = "No Screenshots #{Time.now.to_i}"
    click_new_page
    fill_page_form(name: page_name)
    submit_page_form
    assert_on_page_show(page_name)

    # Navigate back to project show
    within '[data-testid="breadcrumb"]' do
      click_link "Demo Project"
    end
    wait_for_turbo

    assert_page_card_has_placeholder(page_name)
    assert_page_version_count(page_name, 0)
  end

  test "page card shows thumbnail after uploading screenshot" do
    navigate_to_demo_project

    # Create a new page
    page_name = "Thumbnail Test #{Time.now.to_i}"
    click_new_page
    fill_page_form(name: page_name)
    submit_page_form
    assert_on_page_show(page_name)

    # Upload a screenshot to this page
    click_link "Upload version"
    fill_screenshot_form(title: "Version 1", image_path: TEST_IMAGE_PATH)
    submit_screenshot_form
    assert_on_screenshot_show

    # Navigate back to project show via breadcrumb
    within find('[data-testid="breadcrumb"]') do
      click_link "Demo Project"
    end
    wait_for_turbo

    assert_page_card_has_thumbnail(page_name)
    assert_page_version_count(page_name, 1)
  end

  test "page card thumbnail updates after uploading second screenshot" do
    navigate_to_demo_project

    # Create a page and upload first screenshot
    page_name = "Multi Version #{Time.now.to_i}"
    click_new_page
    fill_page_form(name: page_name)
    submit_page_form
    assert_on_page_show(page_name)

    click_link "Upload version"
    fill_screenshot_form(title: "V1", image_path: TEST_IMAGE_PATH)
    submit_screenshot_form
    assert_on_screenshot_show

    # Navigate back to page show via breadcrumb
    within find('[data-testid="breadcrumb"]') do
      all("a").last.click
    end
    wait_for_turbo

    # Upload a second screenshot
    click_link "Upload version"
    fill_screenshot_form(title: "V2", image_path: TEST_IMAGE_PATH)
    submit_screenshot_form
    assert_on_screenshot_show

    # Navigate back to project show
    within find('[data-testid="breadcrumb"]') do
      click_link "Demo Project"
    end
    wait_for_turbo

    assert_page_card_has_thumbnail(page_name)
    assert_page_version_count(page_name, 2)
  end
end
