# frozen_string_literal: true

require_relative "application_system_test_case"
require_relative "pages/auth_page"
require_relative "pages/projects_page"
require_relative "pages/pages_page"
require_relative "pages/screenshots_page"

class PageScreenshotsOrderTest < ApplicationSystemTestCase
  include Pages::AuthPage
  include Pages::ProjectsPage
  include Pages::PagesPage
  include Pages::ScreenshotsPage

  setup do
    login_as_test_user
  end

  test "page show lists newest screenshots first" do
    project_name = "Order Project #{SecureRandom.hex(4)}"
    page_name = "Order Page #{SecureRandom.hex(4)}"
    older_title = "Older Version #{SecureRandom.hex(4)}"
    newer_title = "Newer Version #{SecureRandom.hex(4)}"

    create_project(project_name)
    click_new_page
    fill_page_form(name: page_name)
    submit_page_form
    assert_on_page_show(page_name)

    upload_version(older_title)
    navigate_from_screenshot_to_page
    upload_version(newer_title)
    navigate_from_screenshot_to_page

    assert_equal [ newer_title, older_title ], all(SCREENSHOT_CARD_TITLE, minimum: 2).map(&:text).first(2)
  end

  private

  def create_project(name)
    visit_projects
    click_link "New project"
    assert_selector FORM, wait: 10
    fill_project_form(name: name)
    submit_project_form
    assert_flash_notice "Project created."
    assert_on_project_show(name)
  end

  def upload_version(title)
    click_link "Upload version"
    fill_screenshot_form(title: title, image_path: TEST_IMAGE_PATH)
    submit_screenshot_form
    assert_on_screenshot_show
  end

  def navigate_from_screenshot_to_page
    within find(BREADCRUMB) do
      all("a").last.click
    end
    wait_for_turbo
    assert_on_page_show
  end
end
