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

    assert_annotation_resolved("Will be resolved")
  end

  test "unresolve a resolved annotation" do
    create_annotation("Will be unresolved")

    resolve_annotation("Will be unresolved")
    wait_for_turbo
    assert_annotation_resolved("Will be unresolved")

    unresolve_annotation("Will be unresolved", reason: "Still broken on mobile")
    wait_for_turbo

    assert_annotation_open("Will be unresolved")
    assert_thread_has_resolved_badge("Will be unresolved")
    assert_thread_has_reopened_badge("Will be unresolved")
    assert_thread_body("Will be unresolved", "Still broken on mobile")
  end

  test "mobile annotation mutations keep the mobile page workspace active" do
    screenshot = Screenshot.order(:created_at, :id).last
    mobile = screenshot.screenshot_images.create!(viewport: :mobile, status: :ready)
    mobile.image.attach(
      io: File.open(TEST_IMAGE_PATH),
      filename: File.basename(TEST_IMAGE_PATH),
      content_type: "image/png"
    )
    screenshot.annotations.create!(
      user: users(:test_user),
      viewport: :mobile,
      x_percent: 30,
      y_percent: 30,
      comment: "Mobile viewport feedback"
    )

    visit page_path(screenshot.page, version_id: screenshot.id, viewport: :mobile)
    assert_selector "[data-testid='viewport-switcher-mobile'][aria-selected='true']", wait: 10
    assert_screenshot_image_loaded
    assert_annotation_visible("Mobile viewport feedback")

    resolve_annotation("Mobile viewport feedback")
    wait_for_turbo
    assert_match(
      %r{\A/pages/#{screenshot.page_id}\?version_id=#{screenshot.id}&viewport=mobile\z},
      URI.parse(current_url).request_uri
    )
    assert_selector "[data-testid='viewport-switcher-mobile'][aria-selected='true']"

    unresolve_annotation("Mobile viewport feedback", reason: "Still broken on mobile")
    wait_for_turbo
    assert_selector "[data-testid='viewport-switcher-mobile'][aria-selected='true']"
    assert_annotation_open("Mobile viewport feedback")
  end

  test "delete an annotation" do
    create_annotation("Will be deleted")

    within find(ANNOTATION_ITEM, text: "Will be deleted") do
      accept_confirm do
        click_button "Delete"
      end
    end
    wait_for_turbo

    assert_annotation_not_visible("Will be deleted")
  end

  test "annotation pins appear on the canvas" do
    create_annotation("Pin test")

    assert_selector ANNOTATION_PIN, minimum: 1, wait: 10
  end

  test "a typed draft survives a second drawing without retaining the transient annotation" do
    click_on_image_to_annotate
    assert_annotation_form_visible
    fill_annotation_comment("Keep this draft")

    with_playwright_page do |pw_page|
      initial_state = annotorious_state(pw_page)
      assert_equal 1, initial_state["annotationIds"].size
      assert_equal initial_state["pendingAnnotationId"], initial_state["annotationIds"].first

      pw_page.evaluate(<<~JS)
        (() => {
          const workspace = document.querySelector("[data-controller~='annotorious']")
          const controller = window.Stimulus.getControllerForElementAndIdentifier(workspace, "annotorious")
          window.__createdAnnotationIds = []
          controller.anno.on("createAnnotation", annotation => window.__createdAnnotationIds.push(annotation.id))
          controller.anno.setSelected()
        })()
      JS

      draw_annotation(pw_page, x_ratio: 0.65, y_ratio: 0.55)
      pw_page.wait_for_function("() => window.__createdAnnotationIds?.length > 0", timeout: 10_000)
      pw_page.wait_for_function(<<~JS, timeout: 10_000)
        () => {
          const workspace = document.querySelector("[data-controller~='annotorious']")
          const controller = window.Stimulus.getControllerForElementAndIdentifier(workspace, "annotorious")
          return controller.anno.getAnnotations().length === 1
        }
      JS

      final_state = annotorious_state(pw_page)
      transient_id = pw_page.evaluate("window.__createdAnnotationIds.at(-1)")

      assert_equal initial_state["pendingAnnotationId"], final_state["pendingAnnotationId"]
      assert_equal initial_state["annotationIds"], final_state["annotationIds"]
      assert_equal "Keep this draft", final_state["comment"]
      assert_equal 1, final_state["formCount"]
      refute_includes final_state["annotationIds"], transient_id
    end
  end

  test "comment form follows a long screenshot without stealing the canvas scroll position" do
    upload_tall_screenshot

    with_playwright_page do |pw_page|
      canvas = pw_page.locator(".screenshot-canvas")
      canvas.wait_for(state: "visible", timeout: 10_000)
      canvas_top = canvas.evaluate("element => element.getBoundingClientRect().top + window.scrollY")
      pw_page.evaluate("window.scrollTo(0, #{canvas_top.to_f + 900})")

      scroll_before = pw_page.evaluate("window.scrollY")
      sidebar_before = pw_page.locator(".annotation-sidebar").evaluate(<<~JS)
        element => ({
          position: getComputedStyle(element).position,
          top: element.getBoundingClientRect().top,
          bottom: element.getBoundingClientRect().bottom
        })
      JS

      assert_equal "sticky", sidebar_before["position"]
      assert_operator sidebar_before["top"], :>=, 0
      assert_operator sidebar_before["bottom"], :<=, 720

      sidebar_scroll_before = pw_page.locator(".annotation-sidebar").evaluate(<<~JS)
        element => {
          const spacer = document.createElement("div")
          spacer.dataset.testid = "sidebar-scroll-spacer"
          spacer.style.height = "1200px"
          element.querySelector(".annotation-sidebar__list").appendChild(spacer)
          element.scrollTop = element.scrollHeight
          return element.scrollTop
        }
      JS
      assert_operator sidebar_scroll_before, :>, 0

      draw_visible_annotation(pw_page)
      pw_page.locator(ANNOTATION_FORM).wait_for(state: "visible", timeout: 10_000)

      scroll_after = pw_page.evaluate("window.scrollY")
      form_bounds = pw_page.locator(ANNOTATION_FORM).evaluate(<<~JS)
        element => ({
          top: element.getBoundingClientRect().top,
          bottom: element.getBoundingClientRect().bottom,
          focused: element.querySelector("textarea") === document.activeElement
        })
      JS

      assert_in_delta scroll_before, scroll_after, 1
      assert form_bounds["focused"], "The new annotation textarea should retain keyboard focus"
      assert_equal 0, pw_page.locator(".annotation-sidebar").evaluate("element => element.scrollTop")
      assert_operator form_bounds["top"], :>=, 0
      assert_operator form_bounds["bottom"], :<=, 720

      pw_page.locator(COMMENT_FIELD).fill("Long screenshot comment")
      pw_page.locator(SAVE_BUTTON).click
      pw_page.locator(ANNOTATION_FORM).wait_for(state: "detached", timeout: 10_000)
      pw_page.locator(ANNOTATION_ITEM).filter(hasText: "Long screenshot comment").wait_for(
        state: "visible",
        timeout: 10_000
      )

      scroll_after_save = pw_page.evaluate("window.scrollY")
      assert_in_delta scroll_before, scroll_after_save, 1
    end
  ensure
    FileUtils.rm_f(@tall_image_path) if @tall_image_path
  end

  test "narrow screenshots and their annotation pins share a centered coordinate box" do
    create_annotation("Centered pin")

    with_playwright_page do |pw_page|
      geometry = pw_page.evaluate(<<~JS)
        (() => {
          const canvas = document.querySelector(".screenshot-canvas")
          const image = document.querySelector("[data-testid='screenshot-image']")
          const wrapper = image.parentElement
          const pin = document.querySelector(".annotation-pin")
          const canvasRect = canvas.getBoundingClientRect()
          const wrapperRect = wrapper.getBoundingClientRect()

          return {
            canvasCenter: canvasRect.left + canvasRect.width / 2,
            wrapperCenter: wrapperRect.left + wrapperRect.width / 2,
            wrapperWidth: wrapperRect.width,
            canvasWidth: canvasRect.width,
            pinSharesWrapper: pin.parentElement === wrapper
          }
        })()
      JS

      assert_in_delta geometry["canvasCenter"], geometry["wrapperCenter"], 1
      assert_operator geometry["wrapperWidth"], :<=, geometry["canvasWidth"]
      assert geometry["pinSharesWrapper"], "Pins must use the centered image wrapper as their percentage coordinate box"
    end
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

  def upload_tall_screenshot
    require_vips!
    @tall_image_path = Rails.root.join("tmp", "annotation-scroll-#{SecureRandom.hex(6)}.png")
    Vips::Image.black(400, 2400).pngsave(@tall_image_path.to_s)

    within find(BREADCRUMB) do
      all("a").last.click
    end
    wait_for_turbo
    click_link "Upload version"
    fill_screenshot_form(title: "Tall annotation test", image_path: @tall_image_path.to_s)
    submit_screenshot_form
    assert_on_screenshot_show
    assert_screenshot_image_loaded
  end

  def draw_visible_annotation(pw_page)
    draw_annotation(pw_page, x_ratio: 0.3, viewport_y: 300)
  end

  def draw_annotation(pw_page, x_ratio:, y_ratio: nil, viewport_y: nil)
    overlay = pw_page.locator(ANNOTORIOUS_OVERLAY).first
    overlay.wait_for(state: "visible", timeout: 10_000)
    box = overlay.bounding_box
    start_x = box["x"] + (box["width"] * x_ratio)
    start_y = viewport_y || box["y"] + (box["height"] * y_ratio)

    pw_page.mouse.move(start_x, start_y)
    pw_page.mouse.down
    pw_page.mouse.move(start_x + 80, start_y + 60)
    pw_page.mouse.up
  end

  def annotorious_state(pw_page)
    pw_page.evaluate(<<~JS)
      (() => {
        const workspace = document.querySelector("[data-controller~='annotorious']")
        const controller = window.Stimulus.getControllerForElementAndIdentifier(workspace, "annotorious")

        return {
          pendingAnnotationId: controller.pendingAnnotationId,
          annotationIds: controller.anno.getAnnotations().map(annotation => annotation.id),
          comment: document.querySelector(#{COMMENT_FIELD.to_json})?.value,
          formCount: document.querySelectorAll(#{ANNOTATION_FORM.to_json}).length
        }
      })()
    JS
  end
end
