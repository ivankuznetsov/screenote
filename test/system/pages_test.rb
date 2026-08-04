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

  test "page workspace omits redundant page edit and delete actions" do
    navigate_to_demo_project
    navigate_to_first_page

    assert_no_link "Edit page"
    assert_no_button "Delete page"
  end

  test "page breadcrumb hides query state and filters the project by path" do
    project = Project.create!(name: "rabata.io", creator: users(:test_user))
    users_page = project.pages.create!(name: "/admin/users?page=1&q=test&selected=149617800")
    project.pages.create!(name: "/admin/settings")
    project.pages.create!(name: "/pricing")

    visit page_path(users_page)

    within BREADCRUMB do
      assert_selector '[data-testid="project-switcher"]', text: "rabata.io"
      assert_link "admin", href: project_path(project, path_prefix: "/admin")
      assert_selector '[data-testid="breadcrumb-current"]', text: "users"
      assert_no_text "page=1"
      assert_no_text "selected=149617800"
    end

    within BREADCRUMB do
      click_link "admin"
    end

    assert_current_path project_path(project, path_prefix: "/admin"), ignore_query: false
    assert_page_card_visible "/admin/users"
    assert_page_card_visible "/admin/settings"
    assert_page_card_not_visible "/pricing"
    assert_no_text "page=1"
  end

  test "project switcher returns to all current pages and opens another project" do
    project = Project.create!(name: "rabata.io", creator: users(:test_user))
    current_page = project.pages.create!(name: "/admin/users?selected=149617800")
    project.pages.create!(name: "/pricing")
    other_project = Project.create!(name: "docs.rabata.io", creator: users(:test_user))

    visit page_path(current_page)

    within '[data-testid="project-switcher"]' do
      assert_selector "option[value='#{project_path(project)}']", text: "All rabata.io pages"
      assert_selector "option[value='#{project_path(other_project)}']", text: "docs.rabata.io"
    end
    select "All rabata.io pages", from: "project-switcher"

    assert_on_project_show("rabata.io")
    assert_page_card_visible "/admin/users"
    assert_page_card_visible "/pricing"
    assert_no_text "selected=149617800"

    select "docs.rabata.io", from: "project-switcher"

    assert_on_project_show("docs.rabata.io")
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

    # Return through project navigation.
    navigate_to_demo_project

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

    navigate_to_demo_project

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
    warm_selected_screenshot_thumbnails

    navigate_to_demo_project

    assert_page_card_has_thumbnail(page_name)
    assert_page_version_count(page_name, 1)
  end

  test "page card selects the responsive candidate for the browser pixel ratio" do
    navigate_to_demo_project

    page_name = "Responsive Thumbnail #{Time.now.to_i}"
    click_new_page
    fill_page_form(name: page_name)
    submit_page_form
    assert_on_page_show(page_name)

    click_link "Upload version"
    fill_screenshot_form(title: "Responsive version", image_path: TEST_IMAGE_PATH)
    submit_screenshot_form
    assert_on_screenshot_show
    warm_selected_screenshot_thumbnails

    navigate_to_demo_project
    assert_page_card_has_thumbnail(page_name)

    with_playwright_page do |pw_page|
      proof = pw_page.evaluate(<<~JS, arg: page_name)
        name => {
          const card = [...document.querySelectorAll("[data-testid='page-card']")]
            .find(candidate => candidate.textContent.includes(name))
          const image = card?.querySelector(".page-card__thumbnail img")
          const candidates = Object.fromEntries(
            image.srcset.split(",").map(candidate => {
              const [url, width] = candidate.trim().split(/\s+/)
              return [width, new URL(url, document.baseURI).href]
            })
          )
          const expectedWidth = window.devicePixelRatio >= 2 ? "960w" : "480w"

          return {
            devicePixelRatio: window.devicePixelRatio,
            expectedUrl: candidates[expectedWidth],
            currentSrc: image.currentSrc,
            representationRequests: performance.getEntriesByType("resource")
              .map(entry => entry.name)
              .filter(url => url.includes("/rails/active_storage/representations/"))
          }
        }
      JS

      assert_equal Float(ENV.fetch("DEVICE_SCALE_FACTOR", "1")), proof["devicePixelRatio"]
      assert_equal proof["expectedUrl"], proof["currentSrc"]
      assert_includes proof["representationRequests"], proof["currentSrc"]
    end
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
    warm_selected_screenshot_thumbnails

    # The upload returns directly to this page's selected-version workspace.
    click_link "Upload version"
    fill_screenshot_form(title: "V2", image_path: TEST_IMAGE_PATH)
    submit_screenshot_form
    assert_on_screenshot_show
    warm_selected_screenshot_thumbnails

    navigate_to_demo_project

    assert_page_card_has_thumbnail(page_name)
    assert_page_version_count(page_name, 2)
  end

  private

  def warm_selected_screenshot_thumbnails
    screenshot_id = Rack::Utils.parse_query(URI.parse(page.current_url).query)["version_id"]
    screenshot = Screenshot.find(screenshot_id)
    image = screenshot.primary_image
    blob_id = image.image.blob.id

    ScreenshotDimensionJob.perform_now(image, blob_id) unless image.status_ready?
    ScreenshotThumbnailJob.perform_now(image.reload, blob_id)
  end
end
