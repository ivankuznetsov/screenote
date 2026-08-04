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

  ANNOTORIOUS_OVERLAY = ".a9s-annotationlayer"

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
      assert_operator geometry["canvasWidth"], :>=, 800
      assert_no_selector ".version-sidebar"

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

      assert_equal 3, dimensions.size
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

      toolbar = pw_page.locator(".review-toolbar").bounding_box
      switcher = pw_page.locator(".viewport-switcher").bounding_box
      version_selector = pw_page.locator(".version-selector").bounding_box

      assert_in_delta switcher["y"], version_selector["y"], 1
      assert_operator version_selector["x"], :>, switcher["x"] + switcher["width"]
      assert_operator toolbar["width"], :>, 1_000
    end
  end

  test "narrow review wraps the version selector and keeps its menu in bounds" do
    screenshot = Screenshot.order(:created_at, :id).last
    tablet = screenshot.screenshot_images.create!(viewport: :tablet, status: :ready)
    tablet.image.attach(
      io: File.open(TEST_IMAGE_PATH),
      filename: "tablet.png",
      content_type: "image/png"
    )

    visit page_path(screenshot.page, version_id: screenshot.id)
    assert_selector ".viewport-switcher", wait: 10

    with_playwright_page do |pw_page|
      pw_page.set_viewport_size(width: 720, height: 720)
      pw_page.locator(".version-selector__summary").click
      pw_page.locator(".version-selector__menu").wait_for(state: "visible", timeout: 10_000)

      geometry = pw_page.evaluate(<<~JS)
        (() => {
          const rect = selector => document.querySelector(selector).getBoundingClientRect()
          const toolbar = rect(".review-toolbar")
          const switcher = rect(".viewport-switcher")
          const selector = rect(".version-selector")
          const menu = rect(".version-selector__menu")

          return {
            viewportWidth: window.innerWidth,
            viewportHeight: window.innerHeight,
            toolbar: { left: toolbar.left, right: toolbar.right },
            switcher: { bottom: switcher.bottom },
            selector: { left: selector.left, right: selector.right, top: selector.top },
            menu: {
              left: menu.left,
              right: menu.right,
              top: menu.top,
              bottom: menu.bottom
            }
          }
        })()
      JS

      assert_operator geometry.dig("selector", "top"), :>, geometry.dig("switcher", "bottom")
      assert_in_delta geometry.dig("toolbar", "left"), geometry.dig("selector", "left"), 1
      assert_in_delta geometry.dig("toolbar", "right"), geometry.dig("selector", "right"), 1
      assert_operator geometry.dig("menu", "left"), :>=, geometry.dig("selector", "left") - 1
      assert_operator geometry.dig("menu", "right"), :<=, geometry.dig("selector", "right") + 1
      assert_operator geometry.dig("menu", "left"), :>=, 0
      assert_operator geometry.dig("menu", "right"), :<=, geometry["viewportWidth"]
      assert_operator geometry.dig("menu", "top"), :>=, 0
      assert_operator geometry.dig("menu", "bottom"), :<=, geometry["viewportHeight"]
    end
  end

  test "fullscreen review fills the viewport and floats the annotation sidebar" do
    toggle = "[data-testid='review-fullscreen-toggle']"
    comments_toggle = "[data-testid='review-comments-toggle']"

    assert_selector "#{toggle}[aria-label='Enter fullscreen']", wait: 10
    find(toggle).click

    assert_selector ".screenshot-workspace--fullscreen", wait: 10
    assert_selector "body.review-fullscreen-open"
    assert_selector "#{toggle}[aria-label='Restore view']"
    assert_selector "#{toggle} .screenshot-fullscreen-toggle__icon--restore", visible: true
    assert_selector "#{comments_toggle}[aria-label='Hide comments'][aria-expanded='true']"
    assert_selector ".annotation-sidebar", visible: true

    with_playwright_page do |pw_page|
      geometry = pw_page.evaluate(<<~JS)
        (() => {
          const workspace = document.querySelector(".screenshot-workspace").getBoundingClientRect()
          const canvas = document.querySelector(".screenshot-canvas").getBoundingClientRect()
          const image = document.querySelector("[data-testid='screenshot-image']").getBoundingClientRect()
          const sidebarElement = document.querySelector(".annotation-sidebar")
          const sidebar = sidebarElement.getBoundingClientRect()

          return {
            viewport: { width: window.innerWidth, height: window.innerHeight },
            workspace: {
              left: workspace.left,
              top: workspace.top,
              width: workspace.width,
              height: workspace.height
            },
            canvas: { left: canvas.left, top: canvas.top, width: canvas.width, height: canvas.height },
            image: { left: image.left, top: image.top, width: image.width, height: image.height },
            sidebar: {
              left: sidebar.left,
              right: sidebar.right,
              top: sidebar.top,
              bottom: sidebar.bottom,
              position: getComputedStyle(sidebarElement).position
            },
            bodyOverflow: getComputedStyle(document.body).overflow
          }
        })()
      JS

      assert_in_delta 0, geometry.dig("workspace", "left"), 1
      assert_in_delta 0, geometry.dig("workspace", "top"), 1
      assert_in_delta geometry.dig("viewport", "width"), geometry.dig("workspace", "width"), 1
      assert_in_delta geometry.dig("viewport", "height"), geometry.dig("workspace", "height"), 1
      assert_in_delta geometry.dig("viewport", "width"), geometry.dig("canvas", "width"), 1
      assert_in_delta geometry.dig("viewport", "height"), geometry.dig("canvas", "height"), 1
      assert_in_delta geometry.dig("viewport", "height"), geometry.dig("image", "height"), 1
      assert_in_delta 0, geometry.dig("image", "top"), 1
      assert_equal "absolute", geometry.dig("sidebar", "position")
      assert_operator geometry.dig("sidebar", "left"), :>, geometry.dig("viewport", "width") / 2
      assert_operator geometry.dig("sidebar", "right"), :<=, geometry.dig("viewport", "width")
      assert_operator geometry.dig("sidebar", "top"), :>, 0
      assert_operator geometry.dig("sidebar", "bottom"), :<=, geometry.dig("viewport", "height")
      assert_equal "hidden", geometry["bodyOverflow"]

      pw_page.set_viewport_size(width: 700, height: 720)
      pw_page.wait_for_function(<<~JS)
        () => Math.abs(document.querySelector("[data-testid='screenshot-image']").getBoundingClientRect().width - 700) <= 1
      JS
      narrow_image = pw_page.locator("[data-testid='screenshot-image']").bounding_box
      narrow_sidebar = pw_page.locator(".annotation-sidebar").bounding_box

      assert_in_delta 700, narrow_image["width"], 1
      assert_in_delta 525, narrow_image["height"], 1
      assert_in_delta 4.0 / 3, narrow_image["width"].to_f / narrow_image["height"], 0.01
      assert_operator narrow_sidebar["x"], :>=, 0
      assert_operator narrow_sidebar["x"] + narrow_sidebar["width"], :<=, 700
    end

    find(comments_toggle).click

    assert_selector ".screenshot-workspace--comments-collapsed"
    assert_selector "body.review-fullscreen-comments-collapsed"
    assert_selector "#{comments_toggle}[aria-label='Show comments'][aria-expanded='false']"
    assert_no_selector ".annotation-sidebar", visible: true

    click_on_image_to_annotate

    assert_selector ".screenshot-workspace--comments-collapsed"
    assert_selector "body.review-fullscreen-comments-collapsed"
    assert_selector "#{comments_toggle}[aria-label='Show comments'][aria-expanded='false']"
    assert_no_selector ".annotation-sidebar", visible: true
    assert_in_place_annotation_form_visible
    with_playwright_page do |pw_page|
      assert pw_page.locator(COMMENT_FIELD).evaluate("element => element === document.activeElement"),
        "Starting an annotation should focus its in-place comment field"
    end
    assert_selector ".screenshot-workspace--fullscreen"
    fill_annotation_comment("Fullscreen annotation")
    submit_annotation
    wait_for_turbo

    assert_selector ANNOTATION_ITEM, text: "Fullscreen annotation", visible: :all
    assert_selector ".screenshot-workspace--fullscreen"
    assert_selector "body.review-fullscreen-open"
    assert_selector ".screenshot-workspace--comments-collapsed"
    assert_selector "#{toggle}[aria-label='Restore view']"

    find(comments_toggle).click
    assert_annotation_visible("Fullscreen annotation")
    click_link "Open"
    wait_for_turbo
    assert_selector ".annotation-filter--active", text: "Open"

    assert_annotation_visible("Fullscreen annotation")
    assert_selector ".screenshot-workspace--fullscreen"
    assert_selector "body.review-fullscreen-open"

    find(comments_toggle).click
    assert_selector ".screenshot-workspace--comments-collapsed"
    page.execute_script("document.querySelector('.annotation-filter').click()")
    wait_for_turbo

    assert_selector ".screenshot-workspace--fullscreen"
    assert_selector ".screenshot-workspace--comments-collapsed"
    assert_selector "body.review-fullscreen-comments-collapsed"
    assert_selector "#{comments_toggle}[aria-label='Show comments'][aria-expanded='false']"
    assert_no_selector ".annotation-sidebar", visible: true

    find("body").send_keys(:escape)

    assert_no_selector ".screenshot-workspace--fullscreen"
    assert_no_selector ".screenshot-workspace--comments-collapsed"
    assert_no_selector "body.review-fullscreen-open"
    assert_no_selector "body.review-fullscreen-comments-collapsed"
    assert_selector "#{toggle}[aria-label='Enter fullscreen']"

    find(toggle).click
    assert_no_selector ".screenshot-workspace--comments-collapsed"
    assert_no_selector "body.review-fullscreen-comments-collapsed"
    assert_selector "#{comments_toggle}[aria-label='Hide comments'][aria-expanded='true']"
    assert_selector ".annotation-sidebar", visible: true
    find("#{toggle}[aria-label='Restore view']").click
    assert_no_selector ".screenshot-workspace--fullscreen"
  end

  test "create an annotation by clicking on the image" do
    click_on_image_point

    assert_in_place_annotation_form_visible
    assert_equal(
      { "width" => "", "height" => "" },
      annotation_form_raw_size
    )
    fill_annotation_comment("First annotation from e2e test")
    submit_annotation
    wait_for_turbo

    assert_annotation_visible("First annotation from e2e test")
    assert_annotation_count(1)
    assert_selector POINT_ANNOTATION_PIN, text: "TE", wait: 10
  end

  test "a second point replaces an empty point draft" do
    click_on_image_point(x_ratio: 0.15, y_ratio: 0.2)
    assert_in_place_annotation_form_visible

    with_playwright_page do |pw_page|
      initial_state = annotorious_state(pw_page)
      initial_coords = annotation_form_coords(pw_page)
      initial_form = pw_page.locator(IN_PLACE_ANNOTATION_FORM).bounding_box
      initial_pin = pw_page.locator(DRAFT_POINT_ANNOTATION_PIN).bounding_box

      click_image_point(pw_page, x_ratio: 0.85, y_ratio: 0.75)
      pw_page.wait_for_function(<<~JS, arg: initial_state["pendingAnnotationId"], timeout: 10_000)
        initialId => {
          const workspace = document.querySelector("[data-controller~='annotorious']")
          const controller = window.Stimulus.getControllerForElementAndIdentifier(workspace, "annotorious")
          return controller.pendingAnnotationId && controller.pendingAnnotationId !== initialId
        }
      JS

      final_state = annotorious_state(pw_page)
      final_coords = annotation_form_coords(pw_page)
      final_form = pw_page.locator(IN_PLACE_ANNOTATION_FORM).bounding_box
      final_pin = pw_page.locator(DRAFT_POINT_ANNOTATION_PIN).bounding_box

      assert_equal 1, final_state["formCount"]
      assert_equal "", final_state["comment"]
      assert_in_delta 15, initial_coords["x"], 0.5
      assert_in_delta 20, initial_coords["y"], 0.5
      assert_in_delta 85, final_coords["x"], 0.5
      assert_in_delta 75, final_coords["y"], 0.5
      assert_operator (final_pin["x"] - initial_pin["x"]).abs, :>, 100
      assert_operator (final_form["x"] - initial_form["x"]).abs, :>, 50
    end
  end

  test "point composer avoids its rendered draft marker in a narrow viewport" do
    with_playwright_page do |pw_page|
      pw_page.set_viewport_size(width: 520, height: 720)
      pw_page.wait_for_function(<<~JS, timeout: 10_000)
        () => document.querySelector("[data-testid='screenshot-image']").getBoundingClientRect().width < 500
      JS

      click_image_point(pw_page, x_ratio: 0.85, y_ratio: 0.3)
      pw_page.locator(IN_PLACE_ANNOTATION_FORM).wait_for(state: "visible", timeout: 10_000)

      assert_composer_within_image_and_clear_of(pw_page, DRAFT_POINT_ANNOTATION_PIN)
    end
  end

  test "dragging an area keeps a visible region and opens the composer beside it" do
    with_playwright_page do |pw_page|
      draw_annotation(
        pw_page,
        x_ratio: 0.2,
        y_ratio: 0.25,
        width_ratio: 0.45,
        height_ratio: 0.3
      )
    end

    assert_in_place_annotation_form_visible
    assert_selector UNSAVED_REGION_OUTLINE, wait: 10

    with_playwright_page do |pw_page|
      form = pw_page.locator(IN_PLACE_ANNOTATION_FORM).bounding_box
      region = pw_page.locator(UNSAVED_REGION_OUTLINE).bounding_box
      image = pw_page.locator("[data-testid='screenshot-image']").bounding_box

      assert_operator form["x"], :>=, image["x"]
      assert_operator form["y"], :>=, image["y"]
      assert_operator form["x"] + form["width"], :<=, image["x"] + image["width"] + 1
      assert_operator form["y"] + form["height"], :<=, image["y"] + image["height"] + 1
      assert_operator region["width"], :>, 1
      assert_operator region["height"], :>, 1

      horizontal_overlap = [ [ form["x"] + form["width"], region["x"] + region["width"] ].min -
        [ form["x"], region["x"] ].max, 0 ].max
      vertical_overlap = [ [ form["y"] + form["height"], region["y"] + region["height"] ].min -
        [ form["y"], region["y"] ].max, 0 ].max
      assert_in_delta 0, horizontal_overlap * vertical_overlap, 1,
        "The in-place composer should not obscure its selected region"
    end

    fill_annotation_comment("Selected area")
    submit_annotation
    wait_for_turbo

    assert_selector REGION_ANNOTATION_PIN, text: "TE", wait: 10
  end

  test "moving and resizing an unsaved area keeps one box and saves edited geometry" do
    annotation_count = Annotation.count
    edited_coords = nil

    with_playwright_page do |pw_page|
      draw_annotation(
        pw_page,
        x_ratio: 0.2,
        y_ratio: 0.25,
        width_ratio: 0.25,
        height_ratio: 0.2
      )
      pw_page.locator(IN_PLACE_ANNOTATION_FORM).wait_for(state: "visible", timeout: 10_000)

      initial_width = annotation_form_coords(pw_page)["width"]
      handle = pw_page.locator(".a9s-edge-handle-right")
      handle.wait_for(state: "visible", timeout: 10_000)
      handle_box = handle.bounding_box

      pw_page.mouse.move(handle_box["x"] + handle_box["width"] / 2, handle_box["y"] + handle_box["height"] / 2)
      pw_page.mouse.down
      pw_page.mouse.move(handle_box["x"] + handle_box["width"] / 2 + 80, handle_box["y"] + handle_box["height"] / 2)
      pw_page.mouse.up
      pw_page.wait_for_function(<<~JS, arg: initial_width, timeout: 10_000)
        initialWidth => Number(document.querySelector('[name="annotation[width_percent]"]').value) > initialWidth
      JS

      state = pw_page.evaluate(<<~JS)
        (() => {
          const workspace = document.querySelector("[data-controller~='annotorious']")
          const controller = window.Stimulus.getControllerForElementAndIdentifier(workspace, "annotorious")
          const annotations = controller.anno.getAnnotations()
          const annotation = controller.anno.getAnnotationById(controller.pendingAnnotationId)

          return {
            annotationCount: annotations.length,
            visibleOutlineCount: document.querySelectorAll(#{UNSAVED_REGION_OUTLINE.to_json}).length,
            legacyDraftRegionCount: document.querySelectorAll(".annotation-pin--draft.annotation-pin--region").length,
            formWidth: Number(document.querySelector('[name="annotation[width_percent]"]').value),
            annotationWidth: controller.parseSelector(annotation.target.selector).width_percent,
            pendingAnnotationId: controller.pendingAnnotationId
          }
        })()
      JS

      assert_equal 1, state["annotationCount"]
      assert_operator state["annotationWidth"], :>, initial_width
      assert_in_delta state["annotationWidth"], state["formWidth"], 0.01
      assert_equal 1, state["visibleOutlineCount"]
      assert_equal 0, state["legacyDraftRegionCount"]

      before_move = annotation_form_coords(pw_page)
      outline = pw_page.locator(UNSAVED_REGION_OUTLINE)
      outline_box = outline.bounding_box
      pw_page.mouse.move(
        outline_box["x"] + outline_box["width"] / 2,
        outline_box["y"] + outline_box["height"] / 2
      )
      pw_page.mouse.down
      pw_page.mouse.move(
        outline_box["x"] + outline_box["width"] / 2 + 40,
        outline_box["y"] + outline_box["height"] / 2 + 30
      )
      pw_page.mouse.up
      pw_page.wait_for_function(<<~JS, arg: before_move, timeout: 10_000)
        beforeMove => {
          const x = Number(document.querySelector('[name="annotation[x_percent]"]').value)
          const y = Number(document.querySelector('[name="annotation[y_percent]"]').value)
          return x > beforeMove.x && y > beforeMove.y
        }
      JS

      moved_state = pw_page.evaluate(<<~JS)
        (() => {
          const workspace = document.querySelector("[data-controller~='annotorious']")
          const controller = window.Stimulus.getControllerForElementAndIdentifier(workspace, "annotorious")
          const annotation = controller.anno.getAnnotationById(controller.pendingAnnotationId)
          const coords = controller.parseSelector(annotation.target.selector)

          return {
            x: coords.x_percent,
            y: coords.y_percent,
            formX: Number(document.querySelector('[name="annotation[x_percent]"]').value),
            formY: Number(document.querySelector('[name="annotation[y_percent]"]').value)
          }
        })()
      JS
      assert_in_delta moved_state["x"], moved_state["formX"], 0.01
      assert_in_delta moved_state["y"], moved_state["formY"], 0.01

      resized_handle_box = handle.bounding_box
      pending_id = state["pendingAnnotationId"]
      pw_page.mouse.move(
        resized_handle_box["x"] + resized_handle_box["width"] / 2,
        resized_handle_box["y"] + resized_handle_box["height"] / 2
      )
      pw_page.mouse.down
      pw_page.mouse.move(
        resized_handle_box["x"] + resized_handle_box["width"] / 2 + 2,
        resized_handle_box["y"] + resized_handle_box["height"] / 2
      )
      pw_page.mouse.up
      pw_page.evaluate("new Promise(resolve => requestAnimationFrame(() => requestAnimationFrame(resolve)))")

      final_state = annotorious_state(pw_page)
      assert_equal pending_id, final_state["pendingAnnotationId"]
      assert_equal 1, final_state["annotationIds"].size
      edited_coords = annotation_form_coords(pw_page)
    end

    fill_annotation_comment("Edited area")
    submit_annotation
    wait_for_turbo

    assert_equal annotation_count + 1, Annotation.count
    saved_annotation = Annotation.order(:id).last
    assert_in_delta edited_coords["x"], saved_annotation.x_percent, 0.01
    assert_in_delta edited_coords["y"], saved_annotation.y_percent, 0.01
    assert_in_delta edited_coords["width"], saved_annotation.width_percent, 0.01
    assert_in_delta edited_coords["height"], saved_annotation.height_percent, 0.01
  end

  test "canceling a point draft removes its composer and marker without persisting" do
    annotation_count = Annotation.count
    click_on_image_point

    assert_in_place_annotation_form_visible
    assert_selector DRAFT_POINT_ANNOTATION_PIN, count: 1, wait: 10
    cancel_annotation

    assert_annotation_form_hidden
    assert_no_selector DRAFT_POINT_ANNOTATION_PIN
    assert_equal annotation_count, Annotation.count
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

  test "annotation actions share one row and the reply composer uses the thread width" do
    create_annotation("Compact thread controls")

    within find(ANNOTATION_ITEM, text: "Compact thread controls") do
      within '[data-testid="annotation-actions"]' do
        assert_button "Reply"
        assert_button "Resolve"
        assert_button "Delete"
      end
      reply_toggle = find(REPLY_TOGGLE)
      reply_toggle.click
      assert_selector '[data-testid="reply-composer"]', visible: true
      reply_toggle.click
      assert_selector '[data-testid="reply-composer"]', visible: false
      assert_equal "false", reply_toggle["aria-expanded"]
      reply_toggle.click
      assert_selector '[data-testid="reply-composer"]', visible: true
    end

    with_playwright_page do |pw_page|
      geometry = pw_page.evaluate(<<~JS)
        (() => {
          const item = [...document.querySelectorAll(#{ANNOTATION_ITEM.to_json})]
            .find(candidate => candidate.textContent.includes("Compact thread controls"))
          const actions = [...item.querySelectorAll('[data-testid="annotation-actions"] button, [data-testid="annotation-actions"] input[type="submit"]')]
          const textarea = item.querySelector(#{REPLY_TEXTAREA.to_json})
          const form = textarea.closest("form")
          const itemRect = item.getBoundingClientRect()
          const textareaRect = textarea.getBoundingClientRect()
          const formStyle = getComputedStyle(form)

          return {
            actionTops: actions.map(action => action.getBoundingClientRect().top),
            contentWidth: itemRect.width - 24,
            textareaWidth: textareaRect.width,
            textareaHeight: textareaRect.height,
            formBorder: formStyle.borderTopWidth,
            formPadding: formStyle.paddingTop
          }
        })()
      JS

      assert_operator geometry["actionTops"].max - geometry["actionTops"].min, :<=, 1
      assert_in_delta geometry["contentWidth"], geometry["textareaWidth"], 2
      assert_operator geometry["textareaHeight"], :>=, 80
      assert_equal "0px", geometry["formBorder"]
      assert_equal "0px", geometry["formPadding"]
    end
  end

  test "unresolve a resolved annotation" do
    create_annotation("Will be unresolved")

    resolve_annotation("Will be unresolved")
    wait_for_turbo
    assert_annotation_resolved("Will be unresolved")

    within find(ANNOTATION_ITEM, text: "Will be unresolved") do
      unresolve_toggle = find(UNRESOLVE_BUTTON)
      unresolve_toggle.click
      assert_selector '[data-testid="unresolve-form"]', visible: true
      unresolve_toggle.click
      assert_selector '[data-testid="unresolve-form"]', visible: false
      assert_equal "false", unresolve_toggle["aria-expanded"]
    end

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

  test "sidebar threads and canvas markers select each other" do
    create_annotation("First linked thread")
    first_annotation = Annotation.find_by!(comment: "First linked thread")

    click_on_image_to_annotate(x_offset: 160, y_offset: 80)
    assert_in_place_annotation_form_visible
    fill_annotation_comment("Second linked thread")
    submit_annotation
    wait_for_turbo
    assert_annotation_visible("Second linked thread")
    second_annotation = Annotation.find_by!(comment: "Second linked thread")

    first_item = find("#{ANNOTATION_ITEM}[data-annotation-id='#{first_annotation.id}']")
    first_item.click

    assert_selector "#{ANNOTATION_ITEM}[data-annotation-id='#{first_annotation.id}'].annotation-item--selected"
    assert_selector "#{ANNOTATION_PIN}[data-annotation-id='#{first_annotation.id}'].annotation-pin--selected[aria-pressed='true']"

    find("#{ANNOTATION_PIN}[data-annotation-id='#{second_annotation.id}']").click

    assert_selector "#{ANNOTATION_ITEM}[data-annotation-id='#{second_annotation.id}'].annotation-item--selected"
    assert_selector "#{ANNOTATION_PIN}[data-annotation-id='#{second_annotation.id}'].annotation-pin--selected[aria-pressed='true']"
    assert_no_selector "#{ANNOTATION_ITEM}[data-annotation-id='#{first_annotation.id}'].annotation-item--selected"
  end

  test "saved marker selection reopens collapsed fullscreen comments" do
    create_annotation("Fullscreen saved marker")
    annotation = Annotation.find_by!(comment: "Fullscreen saved marker")
    fullscreen_toggle = "[data-testid='review-fullscreen-toggle']"
    comments_toggle = "[data-testid='review-comments-toggle']"

    find(fullscreen_toggle).click
    assert_selector ".screenshot-workspace--fullscreen", wait: 10
    find(comments_toggle).click
    assert_selector ".screenshot-workspace--comments-collapsed"
    assert_no_selector ".annotation-sidebar", visible: true

    find("#{ANNOTATION_PIN}[data-annotation-id='#{annotation.id}']").click

    assert_no_selector ".screenshot-workspace--comments-collapsed"
    assert_selector "#{comments_toggle}[aria-label='Hide comments'][aria-expanded='true']"
    assert_selector ".annotation-sidebar", visible: true
    assert_selector "#{ANNOTATION_ITEM}[data-annotation-id='#{annotation.id}'].annotation-item--selected",
      text: "Fullscreen saved marker"
  end

  test "open composer repositions within a resized image without covering its region" do
    with_playwright_page do |pw_page|
      pw_page.locator("[data-testid='review-fullscreen-toggle']").click
      pw_page.locator(".screenshot-workspace--fullscreen").wait_for(state: "visible", timeout: 10_000)
      draw_annotation(
        pw_page,
        x_ratio: 0.45,
        y_ratio: 0.25,
        width_ratio: 0.2,
        height_ratio: 0.2
      )
      pw_page.locator(IN_PLACE_ANNOTATION_FORM).wait_for(state: "visible", timeout: 10_000)
      initial_image_width = pw_page.locator("[data-testid='screenshot-image']").bounding_box["width"]

      pw_page.set_viewport_size(width: 720, height: 720)
      pw_page.wait_for_function(<<~JS, arg: initial_image_width, timeout: 10_000)
        initialWidth => document.querySelector("[data-testid='screenshot-image']").getBoundingClientRect().width < initialWidth - 50
      JS
      pw_page.evaluate("new Promise(resolve => requestAnimationFrame(() => requestAnimationFrame(resolve)))")

      assert_composer_within_image_and_clear_of(pw_page, UNSAVED_REGION_OUTLINE)
    end
  end

  test "project members see distinct author markers and can reply to each other" do
    screenshot = Screenshot.order(:created_at, :id).last
    project = screenshot.page.project
    admin = users(:admin)
    bob = users(:bob)
    project.project_memberships.create!(user: admin, role: :member)
    project.project_memberships.create!(user: bob, role: :member)

    logout
    login_as(admin.email, "password123")
    visit page_path(screenshot.page, version_id: screenshot.id)
    assert_screenshot_image_loaded

    click_on_image_point(x_ratio: 0.42, y_ratio: 0.38)
    assert_in_place_annotation_form_visible
    fill_annotation_comment("Ivan's point comment")
    submit_annotation
    wait_for_turbo
    annotation = Annotation.find_by!(comment: "Ivan's point comment")

    assert_selector "#{POINT_ANNOTATION_PIN}[data-annotation-id='#{annotation.id}']", text: "IK"
    assert_selector "#{ANNOTATION_ITEM}[data-annotation-id='#{annotation.id}'] [data-testid='annotation-author-marker']", text: "IK"

    logout
    login_as(bob.email, "password123")
    visit page_path(screenshot.page, version_id: screenshot.id)
    assert_screenshot_image_loaded

    find("#{ANNOTATION_PIN}[data-annotation-id='#{annotation.id}']").click
    assert_selector "#{ANNOTATION_ITEM}[data-annotation-id='#{annotation.id}'].annotation-item--selected"
    reply_to_annotation("Ivan's point comment", reply: "Bob can reproduce this")
    wait_for_turbo

    assert_thread_reply("Ivan's point comment", reply: "Bob can reproduce this", author: bob.email)
    within find(ANNOTATION_ITEM, text: "Ivan's point comment") do
      assert_selector THREAD_AUTHOR_MARKER, text: "BO"
    end

    root_color = find("#{ANNOTATION_ITEM}[data-annotation-id='#{annotation.id}'] [data-testid='annotation-author-marker']")["data-author-color"]
    reply_color = find("#{ANNOTATION_ITEM}[data-annotation-id='#{annotation.id}'] #{THREAD_AUTHOR_MARKER}")["data-author-color"]
    refute_equal root_color, reply_color

    logout
    login_as(admin.email, "password123")
    visit page_path(screenshot.page, version_id: screenshot.id)

    assert_thread_reply("Ivan's point comment", reply: "Bob can reproduce this", author: bob.email)
    assert_selector "#{POINT_ANNOTATION_PIN}[data-annotation-id='#{annotation.id}']", text: "IK"
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

      draw_annotation(pw_page, x_ratio: 0.82, y_ratio: 0.78)
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
      assert_equal sidebar_scroll_before, pw_page.locator(".annotation-sidebar").evaluate("element => element.scrollTop")
      assert pw_page.locator(ANNOTATION_FORM).evaluate(
        "element => element.parentElement.classList.contains('screenshot-canvas__image-wrapper')"
      )
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

  def click_on_image_point(x_ratio: 0.3, y_ratio: 0.3)
    assert_selector ANNOTORIOUS_OVERLAY, wait: 15

    with_playwright_page do |pw_page|
      click_image_point(pw_page, x_ratio: x_ratio, y_ratio: y_ratio)
    end
  end

  def click_image_point(pw_page, x_ratio:, y_ratio:)
    overlay = pw_page.locator(ANNOTORIOUS_OVERLAY).first
    overlay.wait_for(state: "visible", timeout: 10_000)
    box = overlay.bounding_box

    pw_page.mouse.click(
      box["x"] + (box["width"] * x_ratio),
      box["y"] + (box["height"] * y_ratio)
    )
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

  def draw_annotation(
    pw_page,
    x_ratio:,
    y_ratio: nil,
    viewport_y: nil,
    width_ratio: nil,
    height_ratio: nil
  )
    overlay = pw_page.locator(ANNOTORIOUS_OVERLAY).first
    overlay.wait_for(state: "visible", timeout: 10_000)
    box = overlay.bounding_box
    start_x = box["x"] + (box["width"] * x_ratio)
    start_y = viewport_y || box["y"] + (box["height"] * y_ratio)

    pw_page.mouse.move(start_x, start_y)
    pw_page.mouse.down
    pw_page.mouse.move(
      start_x + (width_ratio ? box["width"] * width_ratio : 80),
      start_y + (height_ratio ? box["height"] * height_ratio : 60)
    )
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

  def annotation_form_raw_size
    {
      "width" => find('[name="annotation[width_percent]"]', visible: false).value,
      "height" => find('[name="annotation[height_percent]"]', visible: false).value
    }
  end


  def assert_composer_within_image_and_clear_of(pw_page, selected_selector)
    geometry = pw_page.evaluate(<<~JS)
      (() => {
        const bounds = selector => {
          const rect = document.querySelector(selector).getBoundingClientRect()
          return { left: rect.left, right: rect.right, top: rect.top, bottom: rect.bottom }
        }

        return {
          form: bounds(#{IN_PLACE_ANNOTATION_FORM.to_json}),
          image: bounds("[data-testid='screenshot-image']"),
          selected: bounds(#{selected_selector.to_json})
        }
      })()
    JS
    form = geometry["form"]
    image = geometry["image"]
    selected = geometry["selected"]
    horizontal_overlap = [ [ form["right"], selected["right"] ].min -
      [ form["left"], selected["left"] ].max, 0 ].max
    vertical_overlap = [ [ form["bottom"], selected["bottom"] ].min -
      [ form["top"], selected["top"] ].max, 0 ].max

    assert_operator form["left"], :>=, image["left"] - 1
    assert_operator form["top"], :>=, image["top"] - 1
    assert_operator form["right"], :<=, image["right"] + 1
    assert_operator form["bottom"], :<=, image["bottom"] + 1
    assert_in_delta 0, horizontal_overlap * vertical_overlap, 1,
      "The in-place composer should not obscure its selected marker or region"
  end
end
