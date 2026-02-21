# frozen_string_literal: true

require_relative "application_system_test_case"
require_relative "pages/auth_page"
require_relative "pages/projects_page"
require_relative "pages/pages_page"
require_relative "pages/screenshots_page"
require_relative "pages/annotations_page"

class AnnotationsTest < ApplicationSystemTestCase
  include Pages::AuthPage
  include Pages::ProjectsPage
  include Pages::PagesPage
  include Pages::ScreenshotsPage
  include Pages::AnnotationsPage

  ANNOTORIOUS_OVERLAY = ".screenshot-canvas svg, .a9s-annotationlayer"

  setup do
    login_as_test_user
    create_screenshot_for_annotation
  end

  test "screenshot show page starts with empty annotations" do
    assert_annotation_sidebar_empty
    assert_annotation_count(0)
  end

  test "create an annotation by clicking on the image" do
    click_on_image_to_annotate

    assert_annotation_form_visible
    fill_annotation_comment("First annotation from e2e test")
    submit_annotation
    wait_for_turbo

    assert_flash_notice "Annotation added."
    assert_annotation_visible("First annotation from e2e test")
    assert_annotation_count(1)
  end

  test "cancel annotation form hides it" do
    click_on_image_to_annotate

    assert_annotation_form_visible
    cancel_annotation

    assert_annotation_form_hidden
  end

  test "create multiple annotations" do
    create_annotation("Annotation One")

    click_on_image_to_annotate(x_offset: 100, y_offset: 50)
    assert_annotation_form_visible
    fill_annotation_comment("Annotation Two")
    submit_annotation
    wait_for_turbo
    assert_annotation_visible("Annotation Two")

    assert_annotation_count(2)
  end

  test "resolve an annotation" do
    create_annotation("Will be resolved")

    resolve_annotation("Will be resolved")
    wait_for_turbo

    assert_flash_notice "Annotation updated."
    assert_annotation_resolved("Will be resolved")
  end

  test "unresolve a resolved annotation" do
    create_annotation("Will be unresolved")

    resolve_annotation("Will be unresolved")
    wait_for_turbo
    assert_annotation_resolved("Will be unresolved")

    unresolve_annotation("Will be unresolved", reason: "Still broken on mobile")
    wait_for_turbo

    assert_flash_notice "Annotation unresolved."
    assert_annotation_open("Will be unresolved")
    assert_thread_has_resolved_badge("Will be unresolved")
    assert_thread_has_reopened_badge("Will be unresolved")
    assert_thread_body("Will be unresolved", "Still broken on mobile")
  end

  test "delete an annotation" do
    create_annotation("Will be deleted")

    within find(ANNOTATION_ITEM, text: "Will be deleted") do
      accept_confirm do
        click_button "Delete"
      end
    end
    wait_for_turbo

    assert_flash_notice "Annotation deleted."
    assert_annotation_not_visible("Will be deleted")
  end

  test "annotation pins appear on the canvas" do
    create_annotation("Pin test")

    assert_selector ANNOTATION_PIN, minimum: 1, wait: 10
  end

  private

  def create_screenshot_for_annotation
    navigate_to_demo_project
    navigate_to_first_page

    click_link "Upload version"
    fill_screenshot_form(title: "Annotation Test #{Time.now.to_i}", image_path: TEST_IMAGE_PATH)
    submit_screenshot_form
    assert_on_screenshot_show
    assert_screenshot_image_loaded
  end

  def create_annotation(comment_text)
    click_on_image_to_annotate
    assert_annotation_form_visible
    fill_annotation_comment(comment_text)
    submit_annotation
    wait_for_turbo
    assert_annotation_visible(comment_text)
  end

  # Draw an annotation rectangle on the image using click-drag via Playwright mouse API.
  def click_on_image_to_annotate(x_offset: 0, y_offset: 0)
    assert_selector ANNOTORIOUS_OVERLAY, wait: 15

    with_playwright_page do |pw_page|
      svg = pw_page.locator(ANNOTORIOUS_OVERLAY).first
      svg.wait_for(state: "visible", timeout: 10_000)

      box = svg.bounding_box
      start_x = box["x"] + (box["width"] * 0.3) + x_offset
      start_y = box["y"] + (box["height"] * 0.3) + y_offset

      pw_page.mouse.move(start_x, start_y)
      pw_page.mouse.down
      pw_page.mouse.move(start_x + 80, start_y + 60)
      pw_page.mouse.up
    end
  end
end
