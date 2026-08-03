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

  test "page workspace lists newest versions first in the selector" do
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
    upload_version(newer_title)

    find("[data-testid='version-selector'] summary").click

    assert_equal [ newer_title, older_title ],
      all(VERSION_SELECTOR_ITEM, minimum: 2).map { |item| item.find(".version-selector__item-title").text }.first(2)
    assert_selector "#{VERSION_SELECTOR_ITEM}[aria-current='page']", text: newer_title, count: 1
    assert_no_selector "[data-testid='version-selector'] img"

    older_link = find(VERSION_SELECTOR_ITEM, text: older_title)
    older_path = URI.parse(older_link[:href]).request_uri
    older_link.click

    assert_current_path older_path, ignore_query: false, wait: 10
    assert_selected_version_title older_title
    assert_screenshot_image_loaded

    find("[data-testid='version-selector'] summary").click
    assert_selector "#{VERSION_SELECTOR_ITEM}[aria-current='page']", text: older_title, count: 1
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
    assert_match %r{\A/pages/\d+\?version_id=\d+\z}, URI.parse(current_url).request_uri
  end
end
