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

  test "desktop review keeps a practical canvas and caps its wide layout" do
    with_playwright_page do |pw_page|
      geometry = pw_page.evaluate(<<~JS)
        (() => {
          const canvas = document.querySelector(".screenshot-canvas")

          return {
            viewportWidth: window.innerWidth,
            canvasWidth: canvas.getBoundingClientRect().width
          }
        })()
      JS

      assert_equal 1280, geometry["viewportWidth"]
      assert_operator geometry["canvasWidth"], :>=, 600

      pw_page.set_viewport_size(width: 1920, height: 720)
      review_width = pw_page.locator("main.main--review").evaluate(
        "element => element.getBoundingClientRect().width"
      )

      assert_in_delta 1800, review_width, 1
    end
  end

  test "page actions share rendered dimensions" do
    with_playwright_page do |pw_page|
      dimensions = pw_page.locator(".page-detail__actions .btn").evaluate_all(<<~JS)
        elements => elements.map(element => {
          const rect = element.getBoundingClientRect()
          return { width: rect.width, height: rect.height }
        })
      JS

      assert_equal 5, dimensions.size
      dimensions.drop(1).each do |dimension|
        assert_in_delta dimensions.first["width"], dimension["width"], 1
        assert_in_delta dimensions.first["height"], dimension["height"], 1
      end
    end
  end

  test "viewport switcher segments share rendered dimensions" do
    screenshot = Screenshot.order(:created_at, :id).last
    %i[tablet mobile].each do |viewport|
      screenshot_image = screenshot.screenshot_images.create!(viewport: viewport, status: :ready)
      screenshot_image.image.attach(
        io: File.open(TEST_IMAGE_PATH),
        filename: "#{viewport}.png",
        content_type: "image/png"
      )
    end

    visit page_path(screenshot.page, version_id: screenshot.id)
    assert_selector ".viewport-switcher__btn", count: 3, wait: 10

    with_playwright_page do |pw_page|
      dimensions = pw_page.locator(".viewport-switcher__btn").evaluate_all(<<~JS)
        elements => elements.map(element => {
          const rect = element.getBoundingClientRect()
          return { width: rect.width, height: rect.height }
        })
      JS

      dimensions.drop(1).each do |dimension|
        assert_in_delta dimensions.first["width"], dimension["width"], 1
        assert_in_delta dimensions.first["height"], dimension["height"], 1
      end
    end
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

  test "a drag can leave the right edge and return before completing" do
    with_playwright_page do |pw_page|
      overlay = pw_page.locator(ANNOTORIOUS_OVERLAY).first
      overlay.wait_for(state: "visible", timeout: 10_000)
      box = overlay.bounding_box
      start_x = box["x"] + (box["width"] * 0.7)
      start_y = box["y"] + (box["height"] * 0.35)

      pw_page.mouse.move(start_x, start_y)
      pw_page.mouse.down
      pw_page.mouse.move(box["x"] + box["width"] + 40, start_y + 40)

      capture = pw_page.evaluate(<<~JS)
        (() => {
          const workspace = document.querySelector("[data-controller~='annotorious']")
          const controller = window.Stimulus.getControllerForElementAndIdentifier(workspace, "annotorious")
          const target = controller.capturedPointerTarget
          const pointerId = controller.capturedPointerId

          return {
            pointerId,
            captured: Boolean(target && pointerId != null && target.hasPointerCapture(pointerId))
          }
        })()
      JS

      assert capture["pointerId"], "The active drawing pointer should be tracked"
      assert capture["captured"], "The drawing target should retain pointer capture outside the screenshot"

      pw_page.mouse.move(
        box["x"] + (box["width"] * 0.85),
        box["y"] + (box["height"] * 0.55)
      )
      pw_page.mouse.up
      pw_page.locator(ANNOTATION_FORM).wait_for(state: "visible", timeout: 10_000)

      coords = annotation_form_coords(pw_page)
      assert_operator coords["x"], :>=, 0
      assert_operator coords["y"], :>=, 0
      assert_operator coords["x"] + coords["width"], :<=, 100
      assert_operator coords["y"] + coords["height"], :<=, 100
    end
  end

  test "annotation geometry clamps every edge and normalizes reverse drags" do
    with_playwright_page do |pw_page|
      geometries = pw_page.evaluate(<<~JS)
        (() => {
          const workspace = document.querySelector("[data-controller~='annotorious']")
          const controller = window.Stimulus.getControllerForElementAndIdentifier(workspace, "annotorious")
          const width = controller.imageTarget.naturalWidth
          const height = controller.imageTarget.naturalHeight
          const parse = geometry => controller.parseSelector({ geometry })

          return {
            left: parse({ x: -width * 0.25, y: height * 0.25, w: width * 0.5, h: height * 0.5 }),
            right: parse({ x: width * 0.75, y: height * 0.25, w: width * 0.5, h: height * 0.5 }),
            top: parse({ x: width * 0.25, y: -height * 0.25, w: width * 0.5, h: height * 0.5 }),
            bottom: parse({ x: width * 0.25, y: height * 0.75, w: width * 0.5, h: height * 0.5 }),
            reverse: parse({ x: width * 0.75, y: height * 0.75, w: -width * 0.5, h: -height * 0.5 }),
            fullyOutside: parse({ x: -width * 0.2, y: height * 0.2, w: width * 0.1, h: height * 0.2 }),
            zeroAtEdge: parse({ x: width, y: height * 0.2, w: width * 0.2, h: height * 0.2 }),
            roundedZero: parse({ x: width * 0.5, y: height * 0.2, w: width * 0.00001, h: height * 0.2 }),
            tinyPoint: parse({ x: width * 0.5, y: height * 0.5, w: width * 0.005, h: height * 0.005 })
          }
        })()
      JS

      assert_equal(
        { "x_percent" => 0, "y_percent" => 25, "width_percent" => 25, "height_percent" => 50 },
        geometries["left"]
      )
      assert_equal(
        { "x_percent" => 75, "y_percent" => 25, "width_percent" => 25, "height_percent" => 50 },
        geometries["right"]
      )
      assert_equal(
        { "x_percent" => 25, "y_percent" => 0, "width_percent" => 50, "height_percent" => 25 },
        geometries["top"]
      )
      assert_equal(
        { "x_percent" => 25, "y_percent" => 75, "width_percent" => 50, "height_percent" => 25 },
        geometries["bottom"]
      )
      assert_equal(
        { "x_percent" => 25, "y_percent" => 25, "width_percent" => 50, "height_percent" => 50 },
        geometries["reverse"]
      )
      assert_nil geometries["fullyOutside"]
      assert_nil geometries["zeroAtEdge"]
      assert_nil geometries["roundedZero"]
      assert_equal(
        { "x_percent" => 50, "y_percent" => 50, "width_percent" => nil, "height_percent" => nil },
        geometries["tinyPoint"]
      )
    end
  end

  test "a clamped zero-area transient is removed before the next drawing" do
    with_playwright_page do |pw_page|
      discarded_ids = pw_page.evaluate(<<~JS)
        (() => {
          const workspace = document.querySelector("[data-controller~='annotorious']")
          const controller = window.Stimulus.getControllerForElementAndIdentifier(workspace, "annotorious")
          const originalRemove = controller.anno.removeAnnotation.bind(controller.anno)
          const discardedIds = []

          controller.anno.removeAnnotation = id => {
            discardedIds.push(id)
            return originalRemove(id)
          }

          controller.handleCreate({
            id: "fully-outside",
            target: {
              selector: {
                geometry: {
                  x: -controller.imageTarget.naturalWidth * 0.2,
                  y: controller.imageTarget.naturalHeight * 0.2,
                  w: controller.imageTarget.naturalWidth * 0.1,
                  h: controller.imageTarget.naturalHeight * 0.2
                }
              }
            }
          })

          return discardedIds
        })()
      JS

      assert_equal [ "fully-outside" ], discarded_ids
      assert_no_selector ANNOTATION_FORM

      draw_annotation(pw_page, x_ratio: 0.3, y_ratio: 0.3)
      pw_page.locator(ANNOTATION_FORM).wait_for(state: "visible", timeout: 10_000)
    end
  end

  test "pointer tracking is released on cancel and reconnects without duplicate listeners" do
    with_playwright_page do |pw_page|
      pw_page.evaluate(<<~JS)
        (() => {
          const workspace = document.querySelector("[data-controller~='annotorious']")
          const controller = window.Stimulus.getControllerForElementAndIdentifier(workspace, "annotorious")
          workspace.dataset.pointerLifecycleInstance = "before-turbo"
          window.__pointerLifecycle = {
            beforeTurbo: { setCalls: 0, releaseCalls: 0, active: new Set() },
            afterTurbo: { setCalls: 0, releaseCalls: 0, active: new Set() }
          }

          const exercise = (target, state, pointerIds) => {
            target.setPointerCapture = pointerId => {
              state.setCalls += 1
              state.active.add(pointerId)
            }
            target.hasPointerCapture = pointerId => state.active.has(pointerId)
            target.releasePointerCapture = pointerId => {
              state.releaseCalls += 1
              state.active.delete(pointerId)
            }

            controller.installBoundaryPointerTracking()
            controller.installBoundaryPointerTracking()

            target.dispatchEvent(new PointerEvent("pointerdown", {
              bubbles: true,
              button: 0,
              isPrimary: true,
              pointerId: pointerIds[0]
            }))
            target.dispatchEvent(new PointerEvent("pointercancel", {
              bubbles: true,
              pointerId: pointerIds[0]
            }))
            target.dispatchEvent(new PointerEvent("pointerdown", {
              bubbles: true,
              button: 0,
              isPrimary: true,
              pointerId: pointerIds[1]
            }))
          }

          const firstTarget = document.querySelector(#{ANNOTORIOUS_OVERLAY.to_json})
          exercise(firstTarget, window.__pointerLifecycle.beforeTurbo, [41, 42])
          document.querySelector(".annotation-filter").click()
        })()
      JS

      pw_page.wait_for_function(<<~JS, timeout: 10_000)
        () => {
          const workspace = document.querySelector("[data-controller~='annotorious']")
          return workspace &&
            workspace.dataset.pointerLifecycleInstance !== "before-turbo" &&
            window.Stimulus.getControllerForElementAndIdentifier(workspace, "annotorious")
        }
      JS

      lifecycle = pw_page.evaluate(<<~JS)
        (() => {
          const workspace = document.querySelector("[data-controller~='annotorious']")
          const controller = window.Stimulus.getControllerForElementAndIdentifier(workspace, "annotorious")
          const target = document.querySelector(#{ANNOTORIOUS_OVERLAY.to_json})
          const state = window.__pointerLifecycle.afterTurbo

          target.setPointerCapture = pointerId => {
            state.setCalls += 1
            state.active.add(pointerId)
          }
          target.hasPointerCapture = pointerId => state.active.has(pointerId)
          target.releasePointerCapture = pointerId => {
            state.releaseCalls += 1
            state.active.delete(pointerId)
          }

          controller.installBoundaryPointerTracking()
          controller.installBoundaryPointerTracking()
          target.dispatchEvent(new PointerEvent("pointerdown", {
            bubbles: true,
            button: 0,
            isPrimary: true,
            pointerId: 51
          }))
          target.dispatchEvent(new PointerEvent("pointercancel", {
            bubbles: true,
            pointerId: 51
          }))

          const serialize = value => ({
            setCalls: value.setCalls,
            releaseCalls: value.releaseCalls,
            active: value.active.size
          })

          return {
            beforeTurbo: serialize(window.__pointerLifecycle.beforeTurbo),
            afterTurbo: serialize(window.__pointerLifecycle.afterTurbo)
          }
        })()
      JS

      assert_equal(
        { "setCalls" => 2, "releaseCalls" => 2, "active" => 0 },
        lifecycle["beforeTurbo"]
      )
      assert_equal(
        { "setCalls" => 1, "releaseCalls" => 1, "active" => 0 },
        lifecycle["afterTurbo"]
      )
    end
  end

  test "a workspace without an attached image disconnects cleanly during Turbo replacement" do
    screenshot = Screenshot.order(:created_at, :id).last
    screenshot.primary_image.image.purge
    visit page_path(screenshot.page, version_id: screenshot.id)
    assert_no_selector "[data-testid='screenshot-image']"

    with_playwright_page do |pw_page|
      pw_page.evaluate(<<~JS)
        (() => {
          const workspace = document.querySelector("[data-controller~='annotorious']")
          workspace.dataset.pointerLifecycleInstance = "no-image-before-turbo"
          window.__annotoriousLifecycleErrors = []
          window.__originalConsoleError = console.error
          console.error = (...args) => {
            window.__annotoriousLifecycleErrors.push(args.map(String).join(" "))
            window.__originalConsoleError(...args)
          }
          document.querySelector(".annotation-filter").click()
        })()
      JS

      pw_page.wait_for_function(<<~JS, timeout: 10_000)
        () => {
          const workspace = document.querySelector("[data-controller~='annotorious']")
          return workspace && workspace.dataset.pointerLifecycleInstance !== "no-image-before-turbo"
        }
      JS

      errors = pw_page.evaluate(<<~JS)
        (() => {
          console.error = window.__originalConsoleError
          return window.__annotoriousLifecycleErrors
        })()
      JS

      assert_empty errors
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

  def annotation_form_coords(pw_page)
    pw_page.evaluate(<<~JS)
      (() => {
        const value = name => Number(document.querySelector(`[name="${name}"]`).value)

        return {
          x: value("annotation[x_percent]"),
          y: value("annotation[y_percent]"),
          width: value("annotation[width_percent]"),
          height: value("annotation[height_percent]")
        }
      })()
    JS
  end
end
