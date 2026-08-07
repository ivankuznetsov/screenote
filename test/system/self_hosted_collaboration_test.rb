# frozen_string_literal: true

# screenote-edition: self_hosted

require_relative "application_system_test_case"
require_relative "pages/projects_page"
require_relative "pages/pages_page"
require_relative "pages/screenshots_page"
require_relative "pages/annotations_page"

class SelfHostedCollaborationTest < ApplicationSystemTestCase
  include Pages::ProjectsPage
  include Pages::PagesPage
  include Pages::ScreenshotsPage
  include Pages::AnnotationsPage

  setup do
    require_deployment_mode!(:self_hosted)
    Capybara.reset_sessions!
    login_as_test_user
    navigate_to_demo_project
    navigate_to_first_page
    click_link "Upload version"
    fill_screenshot_form(title: "U8 collaboration sentinel", image_path: TEST_IMAGE_PATH)
    submit_screenshot_form
    assert_on_screenshot_show
    assert_screenshot_image_loaded
    @screenshot = Screenshot.order(:created_at, :id).last
    @project = @screenshot.page.project
    @project.project_memberships.find_or_create_by!(user: users(:alice)) { |membership| membership.role = :member }
    @project.project_memberships.find_or_create_by!(user: users(:bob)) { |membership| membership.role = :member }
  end

  test "two members see a point thread, distinct markers, and project isolation" do
    annotation = nil
    root_color = nil

    Capybara.using_session(:alice) do
      login_as(users(:alice).email, "password123")
      visit page_path(@screenshot.page, version_id: @screenshot.id)
      click_point(x_ratio: 0.4, y_ratio: 0.35)
      assert_in_place_annotation_form_visible
      fill_annotation_comment("U8 multi-user point sentinel")
      submit_annotation
      assert_annotation_visible("U8 multi-user point sentinel")
      annotation = Annotation.find_by!(comment: "U8 multi-user point sentinel")

      assert_selector ".annotation-pin--point[data-annotation-id='#{annotation.id}']"
      root_marker = find(
        "[data-testid='annotation-item'][data-annotation-id='#{annotation.id}'] " \
        "[data-testid='annotation-author-marker']"
      )
      root_color = root_marker["data-author-color"]
      assert root_marker.text.present?
    end

    Capybara.using_session(:bob) do
      login_as(users(:bob).email, "password123")
      visit page_path(@screenshot.page, version_id: @screenshot.id)
      find(".annotation-pin[data-annotation-id='#{annotation.id}']").click
      reply_to_annotation("U8 multi-user point sentinel", reply: "U8 second-user reply sentinel")

      assert_thread_reply(
        "U8 multi-user point sentinel",
        reply: "U8 second-user reply sentinel",
        author: users(:bob).email
      )
      reply_marker = find(
        "[data-testid='annotation-item'][data-annotation-id='#{annotation.id}'] " \
        "[data-testid='thread-author-marker']"
      )
      assert_not_equal root_color, reply_marker["data-author-color"]
    end

    Capybara.using_session(:alice) do
      visit page_path(@screenshot.page, version_id: @screenshot.id)
      find(".annotation-pin[data-annotation-id='#{annotation.id}']").click
      assert_thread_reply(
        "U8 multi-user point sentinel",
        reply: "U8 second-user reply sentinel",
        author: users(:bob).email
      )
    end

    Capybara.using_session(:bob) do
      isolated_project_path = project_path(projects(:alice_second_project))
      visit isolated_project_path
      assert_current_path isolated_project_path
      assert_selector "h1", text: "Page not found"
      assert_no_text "U8 multi-user point sentinel"
    end
  end

  test "area selection stays linked when selected from the comment sidebar" do
    draw_area
    assert_in_place_annotation_form_visible
    fill_annotation_comment("U8 area-selection sentinel")
    submit_annotation
    assert_annotation_visible("U8 area-selection sentinel")
    annotation = Annotation.find_by!(comment: "U8 area-selection sentinel")

    find("[data-testid='annotation-item'][data-annotation-id='#{annotation.id}']").click

    assert_selector(
      ".annotation-pin--region[data-annotation-id='#{annotation.id}'].annotation-pin--selected"
    )
    assert_selector(
      "[data-testid='annotation-item'][data-annotation-id='#{annotation.id}'].annotation-item--selected"
    )
  end

  private

  def click_point(x_ratio:, y_ratio:)
    assert_selector ".a9s-annotationlayer", wait: 15
    with_playwright_page do |browser_page|
      overlay = browser_page.locator(".a9s-annotationlayer").first
      bounds = overlay.bounding_box
      browser_page.mouse.click(
        bounds.fetch("x") + (bounds.fetch("width") * x_ratio),
        bounds.fetch("y") + (bounds.fetch("height") * y_ratio)
      )
    end
  end

  def draw_area
    assert_selector ".a9s-annotationlayer", wait: 15
    with_playwright_page do |browser_page|
      overlay = browser_page.locator(".a9s-annotationlayer").first
      bounds = overlay.bounding_box
      start_x = bounds.fetch("x") + (bounds.fetch("width") * 0.25)
      start_y = bounds.fetch("y") + (bounds.fetch("height") * 0.25)
      browser_page.mouse.move(start_x, start_y)
      browser_page.mouse.down
      browser_page.mouse.move(start_x + 100, start_y + 80)
      browser_page.mouse.up
    end
  end
end
