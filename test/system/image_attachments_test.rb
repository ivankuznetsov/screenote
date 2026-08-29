# frozen_string_literal: true

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
  ATTACHMENT_ALT = '[data-testid="attachment-alt-input"]'
  COMPOSER_ERRORS = '[data-testid="composer-errors"]'
  GALLERY = '[data-testid="image-attachment-gallery"]'
  THUMBNAIL = '[data-testid="attachment-thumbnail"]'
  VIEWER = '[data-testid="attachment-viewer"]'
  VIEWER_IMAGE = '[data-testid="attachment-viewer-image"]'
  VIEWER_CLOSE = '[data-testid="attachment-viewer-close"]'
  VIEWER_NEXT = '[data-testid="attachment-viewer-next"]'
  SECOND_IMAGE_PATH = Rails.root.join("test/fixtures/files/test_image.png").to_s

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

  test "the overlay composer stays a compact rail inside the image" do
    open_root_composer
    attach_file_to_composer(TEST_IMAGE_PATH)
    assert_selector "#{ATTACHMENT_ITEM}[data-state=ready]", wait: 15

    with_playwright_page do |pw_page|
      geometry = pw_page.evaluate(<<~JS)
        (() => {
          const form = document.querySelector("#annotation-form")
          const image = document.querySelector("[data-testid='screenshot-image']")
          const items = document.querySelector(".image-attachment-composer__items")
          const formRect = form.getBoundingClientRect()
          const imageRect = image.getBoundingClientRect()
          const itemsRect = items.getBoundingClientRect()

          return {
            withinImage: formRect.left >= imageRect.left - 1 && formRect.top >= imageRect.top - 1 &&
                         formRect.right <= imageRect.right + 1 && formRect.bottom <= imageRect.bottom + 1,
            direction: getComputedStyle(items).flexDirection,
            railHeight: itemsRect.height,
            rowCount: items.children.length
          }
        })()
      JS

      assert geometry["withinImage"], "the clamped overlay must stay inside the image"
      assert_equal "row", geometry["direction"]
      assert_equal 1, geometry["rowCount"]
      assert_operator geometry["railHeight"], :<=, 80
    end
  end

  test "pasting an image into the composer attaches it and pasted text stays text" do
    open_root_composer

    prevented = with_playwright_page do |pw_page|
      pw_page.locator(ATTACH_BUTTON).wait_for(state: "visible", timeout: 10_000)
      pw_page.evaluate(<<~JS)
        (async () => {
          #{IMAGE_FILE_HELPER}
          const file = await screenoteTestImageFile("pasted.png")
          const transfer = new DataTransfer()
          transfer.items.add(file)
          transfer.setData("text/plain", "pasted words")
          const form = document.querySelector("#annotation-form")
          const event = new ClipboardEvent("paste", { clipboardData: transfer, bubbles: true, cancelable: true })

          // dispatchEvent returns false only when a listener cancelled the
          // event, which is what would swallow the text half of the paste.
          return !form.dispatchEvent(event)
        })()
      JS
    end

    assert_selector "#{ATTACHMENT_ITEM}[data-state=ready]", wait: 15
    assert_equal false, prevented, "a mixed paste must leave the browser's own text insertion alone"
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

  test "an unreadable file reports a specific error and can be removed" do
    open_root_composer
    attach_file_to_composer(Rails.root.join("test/fixtures/files/test_invalid.gif").to_s)

    assert_selector "#{ATTACHMENT_ITEM}[data-state=failed]", wait: 15
    assert_selector ATTACHMENT_STATE, text: /PNG, JPEG, or WebP|could not be read/, wait: 10

    find(ATTACHMENT_REMOVE).click
    assert_no_selector ATTACHMENT_ITEM, wait: 10
  end

  test "an invalid post keeps the composer, the body, and the ready image" do
    open_root_composer
    attach_file_to_composer(TEST_IMAGE_PATH)
    assert_selector "#{ATTACHMENT_ITEM}[data-state=ready]", wait: 15

    with_playwright_page do |pw_page|
      pw_page.evaluate("document.querySelector('textarea[name=\"annotation[comment]\"]').value = 'x'.repeat(5001)")
    end
    submit_annotation

    assert_selector COMPOSER_ERRORS, wait: 15
    assert_selector "#annotation-form", wait: 5
    assert_selector "#{ATTACHMENT_ITEM}[data-state=ready]", wait: 5
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

    press_key("ArrowRight")
    assert_viewer_shows second_url
    press_key("ArrowLeft")
    assert_viewer_shows first_url

    press_key("Escape")
    assert_no_selector "#{VIEWER}[open]", wait: 10
    assert_equal "attachment-thumbnail", focused_testid, "closing must restore focus to the trigger"
  end

  test "the gallery renders at a narrow width" do
    post_annotation_with_attachment("Narrow layout")

    with_playwright_page do |pw_page|
      pw_page.set_viewport_size(width: 480, height: 800)
      box = pw_page.locator(THUMBNAIL).first.bounding_box

      assert_operator box["width"], :>, 0
      assert_operator box["x"] + box["width"], :<=, 480
    end
  end

  test "the composer exposes explicit light and dark component contexts" do
    open_root_composer

    assert_selector "#{COMPOSER}.image-attachment-context--dark", visible: :all, wait: 10

    create_annotation_after_cancel("Sidebar context")
    within find(ANNOTATION_ITEM, text: "Sidebar context") do
      find(REPLY_TOGGLE).click
      assert_selector "#{COMPOSER}.image-attachment-context--light", wait: 10
    end
  end

  private

  def open_root_composer
    click_on_image_to_annotate
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

  def create_screenshot_for_annotation
    navigate_to_demo_project
    navigate_to_first_page

    click_link "Upload version"
    fill_screenshot_form(title: "Attachment Test #{Time.now.to_i}", image_path: TEST_IMAGE_PATH)
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
