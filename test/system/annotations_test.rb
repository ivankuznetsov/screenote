# frozen_string_literal: true

require_relative "application_system_test_case"
require_relative "pages/auth_page"
require_relative "pages/projects_page"
require_relative "pages/screenshots_page"
require_relative "pages/annotations_page"

class AnnotationsTest < ApplicationSystemTestCase
  include Pages::AuthPage
  include Pages::ProjectsPage
  include Pages::ScreenshotsPage
  include Pages::AnnotationsPage

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
    # First annotation
    click_on_image_to_annotate
    assert_annotation_form_visible
    fill_annotation_comment("Annotation One")
    submit_annotation
    wait_for_turbo
    assert_annotation_visible("Annotation One")

    # Second annotation (click a different spot)
    click_on_image_to_annotate(x_offset: 100, y_offset: 50)
    assert_annotation_form_visible
    fill_annotation_comment("Annotation Two")
    submit_annotation
    wait_for_turbo
    assert_annotation_visible("Annotation Two")

    assert_annotation_count(2)
  end

  test "resolve an annotation" do
    # Create an annotation first
    click_on_image_to_annotate
    assert_annotation_form_visible
    fill_annotation_comment("Will be resolved")
    submit_annotation
    wait_for_turbo
    assert_annotation_visible("Will be resolved")

    # Resolve it
    within find(ANNOTATION_ITEM, text: "Will be resolved") do
      click_button "Resolve"
    end
    wait_for_turbo

    assert_flash_notice "Annotation updated."
    assert_annotation_resolved("Will be resolved")
  end

  test "delete an annotation" do
    # Create an annotation first
    click_on_image_to_annotate
    assert_annotation_form_visible
    fill_annotation_comment("Will be deleted")
    submit_annotation
    wait_for_turbo
    assert_annotation_visible("Will be deleted")

    # Delete it
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
    click_on_image_to_annotate
    assert_annotation_form_visible
    fill_annotation_comment("Pin test")
    submit_annotation
    wait_for_turbo

    assert_selector ANNOTATION_PIN, minimum: 1, wait: 10
  end

  private

  def create_screenshot_for_annotation
    visit_projects
    click_project("Demo Project")
    assert_on_project_show("Demo Project")

    click_link "Upload screenshot"

    screenshot_title = "Annotation Test #{Time.now.to_i}"
    image_path = Rails.root.join("test/fixtures/files/test_image.png").to_s
    fill_screenshot_form(title: screenshot_title, image_path: image_path)
    submit_screenshot_form
    assert_on_screenshot_show
    assert_screenshot_image_loaded
  end

  # Click on the image to start creating an annotation using Annotorious.
  # Uses Playwright's low-level mouse API to simulate click-click drawing mode:
  # first click sets the start point, second click completes the annotation.
  def click_on_image_to_annotate(x_offset: 0, y_offset: 0)
    # Wait for the Annotorious SVG overlay to be injected into the DOM
    assert_selector ".screenshot-canvas svg, .a9s-annotationlayer", wait: 15

    with_playwright_page do |pw_page|
      # Wait for the Annotorious SVG container that sits over the image
      svg = pw_page.locator(".screenshot-canvas svg, .a9s-annotationlayer").first
      svg.wait_for(state: "visible", timeout: 10_000)

      box = svg.bounding_box

      # Calculate click positions within the SVG overlay area
      start_x = box["x"] + (box["width"] * 0.3) + x_offset
      start_y = box["y"] + (box["height"] * 0.3) + y_offset
      end_x = start_x + 80
      end_y = start_y + 60

      # Click-click drawing mode: first click starts, second click finishes
      pw_page.mouse.click(start_x, start_y)
      # Brief pause for Annotorious to register the first click
      pw_page.wait_for_timeout(200)
      pw_page.mouse.click(end_x, end_y)
    end
  end
end
