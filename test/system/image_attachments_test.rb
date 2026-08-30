# frozen_string_literal: true

require "timeout"
require_relative "application_system_test_case"
require_relative "pages/auth_page"
require_relative "pages/projects_page"
require_relative "pages/pages_page"
require_relative "pages/screenshots_page"
require_relative "pages/annotations_page"

class ImageAttachmentsTest < ApplicationSystemTestCase
  include Pages::AuthPage
  include Pages::ProjectsPage
  include Pages::PagesPage
  include Pages::ScreenshotsPage
  include Pages::AnnotationsPage

  ANNOTORIOUS_OVERLAY = ".a9s-annotationlayer"
  COMPOSER = '[data-testid="image-attachment-composer"]'
  FILE_INPUT = "#{COMPOSER} input[type=file]"
  ATTACH_BUTTON = '[data-testid="attach-image-button"]'
  ATTACHMENT_ITEM = '[data-testid="attachment-item"]'
  ATTACHMENT_STATE = '[data-testid="attachment-state"]'
  ATTACHMENT_REMOVE = '[data-testid="attachment-remove"]'
  ATTACHMENT_RETRY = '[data-testid="attachment-retry"]'
  ATTACHMENT_ALT = '[data-testid="attachment-alt-input"]'
  ATTACHMENT_STATUS = '[data-testid="attachment-status"]'
  COMPOSER_ERRORS = '[data-testid="composer-errors"]'
  GALLERY = '[data-testid="image-attachment-gallery"]'
  THUMBNAIL = '[data-testid="attachment-thumbnail"]'
  VIEWER = '[data-testid="attachment-viewer"]'
  VIEWER_IMAGE = '[data-testid="attachment-viewer-image"]'
  VIEWER_CLOSE = '[data-testid="attachment-viewer-close"]'
  VIEWER_NEXT = '[data-testid="attachment-viewer-next"]'
  SECOND_IMAGE_PATH = Rails.root.join("test/fixtures/files/test_image.png").to_s
  # Phone-sized, so a layout claim is made where the space actually runs out.
  NARROW_VIEWPORT = [ 480, 800 ].freeze

  # Drag and clipboard payloads have to be synthesized inside the page, and a
  # canvas is the only PNG a page script can produce without a file picker.
  IMAGE_FILE_HELPER = <<~JS
    async function screenoteTestImageFile(name) {
      const canvas = document.createElement("canvas")
      canvas.width = 8
      canvas.height = 8
      const blob = await new Promise(resolve => canvas.toBlob(resolve, "image/png"))
      return new File([blob], name, { type: "image/png" })
    }
  JS

  setup do
    login_as_test_user
    create_screenshot_for_annotation
  end

  test "posts a root annotation with a picked image" do
    open_root_composer
    attach_file_to_composer(TEST_IMAGE_PATH)
    assert_selector "#{ATTACHMENT_ITEM}[data-state=ready]", wait: 15

    fill_annotation_comment("Broken button")
    submit_annotation
    wait_for_turbo

    assert_annotation_visible("Broken button")
    assert_selector "#{GALLERY} #{THUMBNAIL}", count: 1, wait: 15
  end

  # Plan Unit 3 requires the clamped overlay rail to stay off the region the
  # person just selected. That is a claim about real geometry, so it is measured
  # against a full-size page capture rather than a thumbnail-sized fixture: on a
  # 1440x900 screenshot the placement has somewhere to go, and "somewhere" has
  # to be provably clear of the selection.
  test "the overlay composer never covers the selected region on a full-size screenshot" do
    create_screenshot_for_annotation(image_path: DESKTOP_SCREENSHOT_PATH)

    open_root_composer
    attach_file_to_composer(TEST_IMAGE_PATH)
    assert_selector "#{ATTACHMENT_ITEM}[data-state=ready]", wait: 15

    geometry = overlay_geometry

    assert_operator geometry["imageWidth"], :>=, 600,
      "the overlap claim is only meaningful against a real screenshot"
    assert geometry["withinImage"], "the clamped overlay must stay inside the image"
    assert_equal 0, geometry["overlapArea"],
      "the rail must not cover the selected region: #{geometry.inspect}"
    assert_equal "row", geometry["direction"]
    assert_equal 1, geometry["rowCount"]
    assert_operator geometry["railHeight"], :<=, 80
    capture_evidence("overlay-rail-clear-of-selection", facts: { geometry: geometry })
  end

  test "the overlay composer stays a compact rail inside the image" do
    open_root_composer
    attach_file_to_composer(TEST_IMAGE_PATH)
    assert_selector "#{ATTACHMENT_ITEM}[data-state=ready]", wait: 15

    geometry = overlay_geometry

    assert geometry["withinImage"], "the clamped overlay must stay inside the image"
    assert_equal "row", geometry["direction"]
    assert_equal 1, geometry["rowCount"]
    assert_operator geometry["railHeight"], :<=, 80
  end

  # A synthetic ClipboardEvent never performs the browser's own text insertion,
  # so this pastes for real: the clipboard carries both halves and the keystroke
  # produces a trusted event. Only that can show the text actually lands.
  test "pasting an image into the composer attaches it and pasted text stays text" do
    open_root_composer

    with_playwright_page do |pw_page|
      pw_page.locator(ATTACH_BUTTON).wait_for(state: "visible", timeout: 10_000)
      pw_page.context.grant_permissions(%w[clipboard-read clipboard-write])
      pw_page.evaluate(<<~JS)
        (async () => {
          #{IMAGE_FILE_HELPER}
          const file = await screenoteTestImageFile("pasted.png")
          await navigator.clipboard.write([
            new ClipboardItem({
              "image/png": file,
              "text/plain": new Blob(["pasted words"], { type: "text/plain" })
            })
          ])
        })()
      JS
      pw_page.locator("#annotation-form textarea").click
      pw_page.keyboard.press("ControlOrMeta+V")
    end

    assert_selector "#{ATTACHMENT_ITEM}[data-state=ready]", wait: 15
    assert_equal "pasted words", composer_body, "the text half of a mixed paste must reach the textarea"
  end

  test "dropping an image on the composer attaches it and dropping on the canvas does not" do
    open_root_composer

    # The screenshot keeps its Annotorious drag behavior: the composer only
    # claims drops that land on the form itself.
    drop_image_on("[data-testid='screenshot-image']")
    assert_no_selector ATTACHMENT_ITEM, wait: 3

    drop_image_on("#annotation-form")
    assert_selector "#{ATTACHMENT_ITEM}[data-state=ready]", wait: 15
  end

  # A browser leaves `dataTransfer.files` empty until the drop itself, so this
  # is the only shape that proves a real OS drag is accepted: dragover must be
  # cancelled from `types` alone, or the browser navigates to the file instead.
  test "a system drag that exposes no files until the drop still attaches" do
    open_root_composer

    accepted = with_playwright_page do |pw_page|
      pw_page.evaluate(<<~JS)
        (async () => {
          #{IMAGE_FILE_HELPER}
          const form = document.querySelector("#annotation-form")

          // An OS drag in progress: `types` announces files, `files` is empty.
          const hovering = new DataTransfer()
          hovering.items.add(new File([], "placeholder.png", { type: "image/png" }))
          hovering.items.clear()
          Object.defineProperty(hovering, "types", { value: ["Files"] })
          const dragover = new DragEvent("dragover", {
            dataTransfer: hovering, bubbles: true, cancelable: true
          })
          const claimed = !form.dispatchEvent(dragover)

          const dropped = new DataTransfer()
          dropped.items.add(await screenoteTestImageFile("dragged.png"))
          form.dispatchEvent(new DragEvent("drop", { dataTransfer: dropped, bubbles: true, cancelable: true }))

          return claimed
        })()
      JS
    end

    assert_equal true, accepted, "dragover must be cancelled from types alone, before files are readable"
    assert_selector "#{ATTACHMENT_ITEM}[data-state=ready]", wait: 15
  end

  # Cancelling is the one client action that throws a draft away, which is what
  # makes "finish or discard one first" true when the open-batch ceiling is hit.
  # Ordinary disconnect and navigation still leave the batch for its 24 hour
  # recovery window, so nothing else may issue this request.
  test "cancelling the overlay discards its draft batch" do
    open_root_composer
    attach_file_to_composer(TEST_IMAGE_PATH)
    assert_selector "#{ATTACHMENT_ITEM}[data-state=ready]", wait: 15

    discards = record_batch_discards
    cancel_annotation

    assert_no_selector "#annotation-form", wait: 10
    Timeout.timeout(10) { sleep 0.05 until discards.any? }
    assert_equal 1, discards.size
  end

  test "an unreadable file reports a specific error and can be removed" do
    open_root_composer
    attach_file_to_composer(Rails.root.join("test/fixtures/files/test_invalid.png").to_s)

    assert_selector "#{ATTACHMENT_ITEM}[data-state=failed]", wait: 15
    assert_selector ATTACHMENT_STATE, text: /PNG, JPEG, or WebP|could not be read/, wait: 10
    assert_no_selector ATTACHMENT_RETRY, visible: :visible

    find(ATTACHMENT_REMOVE).click
    assert_no_selector ATTACHMENT_ITEM, wait: 10
  end

  test "a failed remove stays visible and can be retried safely" do
    open_root_composer
    attach_file_to_composer(TEST_IMAGE_PATH)
    assert_selector "#{ATTACHMENT_ITEM}[data-state=ready]", wait: 15

    with_playwright_page do |pw_page|
      pw_page.route("**/attachments/discard", ->(route, _request) { route.abort })
    end
    find(ATTACHMENT_REMOVE).click

    assert_selector "#{ATTACHMENT_ITEM}[data-state=failed]", wait: 10
    assert_selector ATTACHMENT_STATE, text: /could not be removed/i

    with_playwright_page { |pw_page| pw_page.unroute("**/attachments/discard") }
    find(ATTACHMENT_REMOVE).click
    assert_no_selector ATTACHMENT_ITEM, wait: 10
  end

  test "a Stimulus reconnect restores one ready preview without duplicate listeners" do
    open_root_composer
    attach_file_to_composer(TEST_IMAGE_PATH)
    assert_selector "#{ATTACHMENT_ITEM}[data-state=ready]", count: 1, wait: 15

    with_playwright_page do |pw_page|
      pw_page.evaluate(<<~JS)
        (async () => {
          const composer = document.querySelector('#annotation-form #{COMPOSER}')
          const parent = composer.parentElement
          const next = composer.nextSibling
          composer.remove()
          await new Promise(resolve => setTimeout(resolve, 50))
          parent.insertBefore(composer, next)
        })()
      JS
    end

    assert_selector "#{ATTACHMENT_ITEM}[data-state=ready]", count: 1, wait: 15
    attach_file_to_composer(SECOND_IMAGE_PATH)
    assert_selector "#{ATTACHMENT_ITEM}[data-state=ready]", count: 2, wait: 15

    fill_annotation_comment("Restored once")
    submit_annotation
    wait_for_turbo
    assert_selector "#{GALLERY} #{THUMBNAIL}", count: 2, wait: 15
  end

  test "an invalid post keeps the composer, the body, and the ready image" do
    open_root_composer
    attach_file_to_composer(TEST_IMAGE_PATH)
    assert_selector "#{ATTACHMENT_ITEM}[data-state=ready]", wait: 15

    body = "x" * 5001
    with_playwright_page do |pw_page|
      pw_page.evaluate("document.querySelector('textarea[name=\"annotation[comment]\"]').value = 'x'.repeat(5001)")
    end
    submit_annotation

    assert_selector COMPOSER_ERRORS, wait: 15
    assert_selector "#annotation-form", wait: 5
    assert_selector "#{ATTACHMENT_ITEM}[data-state=ready]", wait: 5
    assert_equal body, composer_body, "a rejected post must keep the text that was typed"
  end

  test "replies carry their own attachments" do
    create_annotation("Needs a screenshot")

    within find(ANNOTATION_ITEM, text: "Needs a screenshot") do
      find(REPLY_TOGGLE).click
      find(REPLY_TEXTAREA).set("Here is the crop")
      attach_file_to_composer(TEST_IMAGE_PATH)
      assert_selector "#{ATTACHMENT_ITEM}[data-state=ready]", wait: 15
      find(REPLY_BUTTON).click
    end
    wait_for_turbo

    assert_selector "#{THREAD_ENTRY} #{GALLERY} #{THUMBNAIL}", count: 1, wait: 15
  end

  # Plan Unit 3 requires batch isolation across composers that are mounted at
  # the same time: a reply composer open while the root overlay is open must
  # take its own batch and keep its own images.
  test "a root composer and a reply composer mounted together stay isolated" do
    create_annotation("Needs a screenshot")

    # A second draw has to land clear of the pin the first annotation left, or
    # Annotorious selects that shape instead of starting a new one.
    open_root_composer(x_offset: 180, y_offset: 140)
    root_form = find("#annotation-form")
    attach_file_to_composer(SECOND_IMAGE_PATH, within: root_form)
    within root_form do
      assert_selector "#{ATTACHMENT_ITEM}[data-state=ready]", count: 1, wait: 15
    end

    within find(ANNOTATION_ITEM, text: "Needs a screenshot") do
      find(REPLY_TOGGLE).click
      find(REPLY_TEXTAREA).set("Here is the crop")
      attach_file_to_composer(TEST_IMAGE_PATH)
      assert_selector "#{ATTACHMENT_ITEM}[data-state=ready]", count: 1, wait: 15
    end

    batch_ids = with_playwright_page do |pw_page|
      pw_page.evaluate(<<~JS)
        Array.from(document.querySelectorAll("input[name='image_attachment_batch_id']"))
          .map(field => field.value)
          .filter(value => value)
      JS
    end

    assert_equal 2, batch_ids.size, "each mounted composer must own a batch"
    assert_equal batch_ids.uniq, batch_ids, "mounted composers must not share one batch"

    # Each composer still shows exactly the one image it was given.
    within find(ANNOTATION_ITEM, text: "Needs a screenshot") do
      assert_selector "#{ATTACHMENT_ITEM}[data-state=ready]", count: 1
      find(REPLY_BUTTON).click
    end
    wait_for_turbo

    assert_selector "#{THREAD_ENTRY} #{GALLERY} #{THUMBNAIL}", count: 1, wait: 15
  end

  test "unresolving carries its own attachments" do
    create_annotation("Fix the header")
    resolve_annotation("Fix the header")
    wait_for_turbo

    within find(ANNOTATION_ITEM, text: "Fix the header") do
      find(UNRESOLVE_BUTTON).click
      within find('[data-testid="unresolve-form"]') do
        find(UNRESOLVE_TEXTAREA).set("Still wrong")
        attach_file_to_composer(TEST_IMAGE_PATH)
        assert_selector "#{ATTACHMENT_ITEM}[data-state=ready]", wait: 15
        find(SUBMIT_UNRESOLVE_BUTTON).click
      end
    end
    wait_for_turbo

    assert_selector THREAD_BADGE_REOPENED, wait: 15
    assert_selector "#{THREAD_ENTRY} #{GALLERY} #{THUMBNAIL}", minimum: 1, wait: 15
  end

  test "alt text is optional and falls back to a neutral label" do
    open_root_composer
    attach_file_to_composer(TEST_IMAGE_PATH)
    assert_selector "#{ATTACHMENT_ITEM}[data-state=ready]", wait: 15
    assert_selector ATTACHMENT_ALT, wait: 5

    fill_annotation_comment("No description")
    submit_annotation
    wait_for_turbo

    assert_selector "#{THUMBNAIL}[data-alt='Attached image']", wait: 15
  end

  test "saving while the alt field is focused waits for its final description" do
    open_root_composer
    attach_file_to_composer(TEST_IMAGE_PATH)
    assert_selector "#{ATTACHMENT_ITEM}[data-state=ready]", wait: 15

    fill_annotation_comment("Described image")
    find(ATTACHMENT_ALT).set("A dialog showing the failed save")
    submit_annotation
    wait_for_turbo

    assert_selector "#{THUMBNAIL}[data-alt='A dialog showing the failed save']", wait: 15
  end

  # A screen reader only learns about an upload from the composer's live region,
  # so the region and the exact text it carries are asserted rather than left to
  # a manual listen.
  test "the composer announces every upload transition in a polite live region" do
    open_root_composer

    assert_selector "#{COMPOSER} [role=status][aria-live=polite]", visible: :all

    attach_file_to_composer(TEST_IMAGE_PATH)
    assert_selector "#{ATTACHMENT_ITEM}[data-state=ready]", wait: 15
    assert_selector ATTACHMENT_STATUS, text: "Image 1 uploaded.", wait: 10

    find(ATTACHMENT_REMOVE).click
    assert_no_selector ATTACHMENT_ITEM, wait: 10
    assert_selector ATTACHMENT_STATUS, text: "Image removed.", wait: 10

    attach_file_to_composer(Rails.root.join("test/fixtures/files/test_invalid.png").to_s)
    assert_selector "#{ATTACHMENT_ITEM}[data-state=failed]", wait: 15
    assert_selector ATTACHMENT_STATUS, text: /Image 1 failed\./, wait: 10
  end

  test "the viewer opens on two images, navigates with the keyboard, and restores focus" do
    open_root_composer
    attach_file_to_composer(TEST_IMAGE_PATH)
    assert_selector "#{ATTACHMENT_ITEM}[data-state=ready]", count: 1, wait: 15
    attach_file_to_composer(SECOND_IMAGE_PATH)
    assert_selector "#{ATTACHMENT_ITEM}[data-state=ready]", count: 2, wait: 15

    fill_annotation_comment("Look at both")
    submit_annotation
    wait_for_turbo

    assert_annotation_visible("Look at both")
    assert_selector "#{GALLERY} #{THUMBNAIL}", count: 2, wait: 15
    first_url, second_url = all(THUMBNAIL).first(2).map { |trigger| trigger["data-original-url"] }
    assert_not_equal first_url, second_url

    all(THUMBNAIL).first.click
    assert_selector "#{VIEWER}[open]", wait: 10
    assert_selector "#{VIEWER_NEXT}:not([hidden])"
    assert_viewer_shows first_url
    assert_equal "attachment-viewer-image", focused_testid, "the dialog must open focus onto its content"

    # The viewer is the only place an attachment can be read at full size, so
    # every control the plan names has to be on it, pointed at the application.
    assert_selector "#{VIEWER}[aria-label='Attached image viewer']"
    assert_selector '[data-testid="attachment-viewer-previous"]'
    assert_selector '[data-testid="attachment-viewer-zoom-in"]'
    assert_selector "[data-testid='attachment-viewer-download'][href^='/media/image_attachments/']"
    assert_selector "[data-testid='attachment-viewer-open-original'][href^='/media/image_attachments/']"
    capture_evidence("viewer-open", facts: gallery_facts)

    press_key("ArrowRight")
    assert_viewer_shows second_url
    press_key("ArrowLeft")
    assert_viewer_shows first_url

    press_key("Escape")
    assert_no_selector "#{VIEWER}[open]", wait: 10
    assert_equal "attachment-thumbnail", focused_testid, "closing must restore focus to the trigger"
  end

  test "the gallery and its viewer render at a narrow width" do
    post_annotation_with_attachment("Narrow layout")

    resize_viewport(NARROW_VIEWPORT)
    with_playwright_page do |pw_page|
      box = pw_page.locator(THUMBNAIL).first.bounding_box

      assert_operator box["width"], :>, 0
      assert_operator box["x"] + box["width"], :<=, NARROW_VIEWPORT.first
    end
    capture_evidence("gallery-narrow-width", facts: gallery_facts)

    # A viewer that overflows the viewport cannot be read on a phone, so the
    # narrow claim covers the full-size view as well as the thumbnails.
    find(THUMBNAIL, match: :first).click
    assert_selector "#{VIEWER}[open]", wait: 10
    with_playwright_page do |pw_page|
      box = pw_page.locator(VIEWER_IMAGE).bounding_box

      assert_operator box["x"], :>=, -1
      assert_operator box["x"] + box["width"], :<=, NARROW_VIEWPORT.first + 1
    end
    capture_evidence("viewer-narrow-width", facts: gallery_facts)
  end

  test "the composer exposes explicit light and dark component contexts" do
    open_root_composer

    assert_selector "#{COMPOSER}.image-attachment-context--dark", visible: :all, wait: 10
    capture_evidence("composer-dark-overlay-context", facts: { context: "dark" })
    resize_viewport(NARROW_VIEWPORT)
    assert_selector "#{COMPOSER}.image-attachment-context--dark", visible: :all, wait: 10
    capture_evidence("composer-dark-overlay-context-narrow", facts: { context: "dark" })
    resize_viewport(SCREEN_SIZE)

    create_annotation_after_cancel("Sidebar context")
    within find(ANNOTATION_ITEM, text: "Sidebar context") do
      find(REPLY_TOGGLE).click
      assert_selector "#{COMPOSER}.image-attachment-context--light", wait: 10
    end
    capture_evidence("composer-light-sidebar-context", facts: { context: "light" })
    resize_viewport(NARROW_VIEWPORT)
    assert_selector "#{COMPOSER}.image-attachment-context--light", wait: 10
    capture_evidence("composer-light-sidebar-context-narrow", facts: { context: "light" })
  end

  # Rendering never processes an image, so a posted gallery shows a neutral
  # placeholder until the post-claim warming job has run. Both halves matter:
  # the placeholder is what a reader sees first, and the responsive thumbnail is
  # what the job is for.
  test "a posted gallery shows a neutral placeholder and warms into responsive thumbnails" do
    create_screenshot_for_annotation(image_path: DESKTOP_SCREENSHOT_PATH)
    post_annotation_with_attachment("Warmed thumbnails")

    assert_selector "#{GALLERY} [data-testid='attachment-placeholder']", count: 1, wait: 15
    assert_selector "#{THUMBNAIL}[data-alt='Attached image']"
    capture_evidence("gallery-pending-placeholder", facts: gallery_facts)

    within find(ANNOTATION_ITEM, text: "Warmed thumbnails") do
      find(REPLY_TOGGLE).click
      find(REPLY_TEXTAREA).set("And here is mine")
      attach_file_to_composer(SECOND_IMAGE_PATH)
      assert_selector "#{ATTACHMENT_ITEM}[data-state=ready]", wait: 15
      find(REPLY_BUTTON).click
    end
    wait_for_turbo
    assert_selector "#{THREAD_ENTRY} #{GALLERY} #{THUMBNAIL}", count: 1, wait: 15

    warm_attachment_thumbnails
    page.refresh
    assert_selector "#{GALLERY} img.image-attachment-gallery__image", count: 2, wait: 15
    assert_no_selector "[data-testid='attachment-placeholder']"

    facts = gallery_facts
    assert facts["thumbnailSources"].all? { |src| src.start_with?("/media/image_attachments/") },
      "thumbnails must be fetched from the application, not the storage provider: #{facts.inspect}"
    assert facts["thumbnailSrcsets"].all? { |set| set.include?("2x") },
      "each thumbnail must offer a 2x source: #{facts.inspect}"
    capture_evidence("gallery-warmed-thumbnails-desktop", facts: facts)
  end

  private

  # The DOM facts a gallery screenshot cannot show on its own: which URL each
  # image came from, whether a 2x source was offered, and how many items are
  # still waiting on the warming job.
  def gallery_facts
    with_playwright_page do |pw_page|
      pw_page.evaluate(<<~JS)
        (() => {
          const triggers = Array.from(document.querySelectorAll("[data-testid='attachment-thumbnail']"))
          const images = Array.from(document.querySelectorAll(".image-attachment-gallery__image"))
          return {
            thumbnailCount: triggers.length,
            placeholderCount: document.querySelectorAll("[data-testid='attachment-placeholder']").length,
            thumbnailSources: images.map(image => new URL(image.src).pathname),
            thumbnailSrcsets: images.map(image => image.getAttribute("srcset") || ""),
            originalUrls: triggers.map(trigger => trigger.dataset.originalUrl),
            downloadUrls: triggers.map(trigger => trigger.dataset.downloadUrl),
            altText: triggers.map(trigger => trigger.dataset.alt)
          }
        })()
      JS
    end
  end

  # The warming job is what turns a placeholder into a thumbnail. Test jobs are
  # enqueued and never run, so evidence for the warmed state has to run it.
  def warm_attachment_thumbnails
    ImageAttachment.submitted.includes(image_attachment: :blob).find_each do |attachment|
      ImageAttachmentThumbnailJob.perform_now(attachment, attachment.image.blob.id)
    end
  end

  # Reads the same numbers the placement algorithm uses: the selected region
  # comes from the form's own percentage fields against the image box, so the
  # measurement cannot drift from what was actually selected.
  def overlay_geometry
    with_playwright_page do |pw_page|
      pw_page.evaluate(<<~JS)
        (() => {
          const form = document.querySelector("#annotation-form")
          const image = document.querySelector("[data-testid='screenshot-image']")
          const items = document.querySelector(".image-attachment-composer__items")
          const formRect = form.getBoundingClientRect()
          const imageRect = image.getBoundingClientRect()
          const itemsRect = items.getBoundingClientRect()
          const percent = name => Number(form.querySelector(`[name='annotation[${name}]']`)?.value) || 0
          const region = {
            left: imageRect.left + (percent("x_percent") / 100) * imageRect.width,
            top: imageRect.top + (percent("y_percent") / 100) * imageRect.height
          }
          region.right = region.left + (percent("width_percent") / 100) * imageRect.width
          region.bottom = region.top + (percent("height_percent") / 100) * imageRect.height
          const overlapWidth = Math.max(
            Math.min(formRect.right, region.right) - Math.max(formRect.left, region.left), 0
          )
          const overlapHeight = Math.max(
            Math.min(formRect.bottom, region.bottom) - Math.max(formRect.top, region.top), 0
          )

          return {
            imageWidth: Math.round(imageRect.width),
            imageHeight: Math.round(imageRect.height),
            formWidth: Math.round(formRect.width),
            formHeight: Math.round(formRect.height),
            regionWidth: Math.round(region.right - region.left),
            regionHeight: Math.round(region.bottom - region.top),
            overlapArea: Math.round(overlapWidth * overlapHeight),
            withinImage: formRect.left >= imageRect.left - 1 && formRect.top >= imageRect.top - 1 &&
                         formRect.right <= imageRect.right + 1 && formRect.bottom <= imageRect.bottom + 1,
            direction: getComputedStyle(items).flexDirection,
            railHeight: Math.round(itemsRect.height),
            rowCount: items.children.length
          }
        })()
      JS
    end
  end

  def open_root_composer(x_offset: 0, y_offset: 0)
    click_on_image_to_annotate(x_offset: x_offset, y_offset: y_offset)
    assert_annotation_form_visible
    assert_selector ATTACH_BUTTON, wait: 10
  end

  def attach_file_to_composer(path, within: nil)
    scope = within || page
    scope.find(FILE_INPUT, visible: :all, match: :first).set(path)
  end

  # Files can only be synthesized in the page, so drag payloads are built there
  # and dispatched at the exact element under test.
  def drop_image_on(selector)
    with_playwright_page do |pw_page|
      pw_page.evaluate(<<~JS)
        (async () => {
          #{IMAGE_FILE_HELPER}
          const file = await screenoteTestImageFile("dropped.png")
          const transfer = new DataTransfer()
          transfer.items.add(file)
          document.querySelector("#{selector}").dispatchEvent(
            new DragEvent("drop", { dataTransfer: transfer, bubbles: true, cancelable: true })
          )
        })()
      JS
    end
  end

  # The overlay and the sidebar composers use different textareas, so the body
  # is read from whichever one the current form owns.
  def composer_body
    with_playwright_page do |pw_page|
      pw_page.evaluate("document.querySelector('#annotation-form textarea')?.value")
    end
  end

  # Only an explicit cancel may discard a draft, so the assertion is on the
  # request itself rather than on any state the page still shows.
  def record_batch_discards
    discards = []
    with_playwright_page do |pw_page|
      pw_page.route("**/image-attachment-drafts/batches/*", lambda do |route, request|
        discards << request.url if request.method == "DELETE"
        route.continue
      end)
    end
    discards
  end

  def resize_viewport(size)
    width, height = size
    with_playwright_page { |pw_page| pw_page.set_viewport_size(width: width, height: height) }
  end

  def press_key(key)
    with_playwright_page { |pw_page| pw_page.keyboard.press(key) }
  end

  def focused_testid
    with_playwright_page { |pw_page| pw_page.evaluate("document.activeElement?.dataset?.testid") }
  end

  def assert_viewer_shows(url)
    assert_selector "#{VIEWER_IMAGE}[src='#{url}']", wait: 10
  end

  def post_annotation_with_attachment(comment)
    open_root_composer
    attach_file_to_composer(TEST_IMAGE_PATH)
    assert_selector "#{ATTACHMENT_ITEM}[data-state=ready]", wait: 15
    fill_annotation_comment(comment)
    submit_annotation
    wait_for_turbo
    assert_annotation_visible(comment)
  end

  def create_annotation_after_cancel(comment)
    cancel_annotation if page.has_selector?("#annotation-form", wait: 1)
    create_annotation(comment)
  end

  def create_screenshot_for_annotation(image_path: TEST_IMAGE_PATH)
    navigate_to_demo_project
    navigate_to_first_page

    click_link "Upload version"
    fill_screenshot_form(title: "Attachment Test #{Time.now.to_i}-#{rand(1000)}", image_path: image_path)
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
