# frozen_string_literal: true

require "test_helper"

class ScreenshotsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:alice)
    @project = projects(:alice_project)
    @page = pages(:alice_page)
    @screenshot = screenshots(:alice_screenshot)
  end

  # Authentication
  test "redirects to sign in when not authenticated" do
    get screenshot_path(@screenshot)
    assert_redirected_to new_session_path
  end

  # Show
  test "show redirects legacy screenshot urls to the page workspace" do
    sign_in(@user)
    get screenshot_path(@screenshot)
    assert_redirected_to page_path(@page, version_id: @screenshot.id)
  end

  test "show redirects a valid legacy viewport url to equivalent page workspace state" do
    sign_in(@user)
    @screenshot.screenshot_images.create!(viewport: :mobile)

    get viewport_screenshot_path(@screenshot, :mobile)

    assert_redirected_to page_path(@page, version_id: @screenshot.id, viewport: :mobile)
  end

  test "show drops an unavailable viewport from a legacy compatibility redirect" do
    sign_in(@user)
    assert_equal %w[desktop], @screenshot.available_viewports

    get viewport_screenshot_path(@screenshot, :mobile)

    assert_redirected_to page_path(@page, version_id: @screenshot.id)
  end

  test "show returns not found for other users screenshot" do
    sign_in(@user)
    get screenshot_path(screenshots(:bob_screenshot))
    assert_response :not_found
  end

  test "show works for project members (not just owners)" do
    # Regression guard: set_screenshot's scope change in PR-3 went from
    # owner-only (Current.user.projects) to membership-scoped. Verify a
    # non-owner member can view screenshots of projects they joined.
    bob = users(:bob)
    assert project_memberships(:bob_member_of_alice_project).present?,
      "Fixture: bob is a member of alice's project"

    sign_in(bob)
    get screenshot_path(@screenshot)

    assert_redirected_to page_path(@page, version_id: @screenshot.id)
  end

  # Viewport switcher
  test "show renders viewport switcher when multiple viewports exist" do
    sign_in(@user)
    @screenshot.screenshot_images.create!(viewport: :mobile)
    @screenshot.screenshot_images.create!(viewport: :tablet)

    get page_path(@page, version_id: @screenshot.id)

    assert_response :success
    assert_select ".viewport-switcher"
    assert_select "[data-testid='viewport-switcher-desktop']"
    assert_select "[data-testid='viewport-switcher-tablet']"
    assert_select "[data-testid='viewport-switcher-mobile']"
  end

  test "show hides viewport switcher for single-viewport legacy screenshots" do
    sign_in(@user)
    assert_equal 1, @screenshot.screenshot_images.count

    get page_path(@page, version_id: @screenshot.id)

    assert_response :success
    assert_select ".viewport-switcher", 0, "No switcher when only one viewport exists"
  end

  test "show at /viewports/:viewport renders the matching variant" do
    sign_in(@user)
    @screenshot.screenshot_images.create!(viewport: :mobile)
    annotations(:point_annotation).update!(viewport: :mobile)

    get page_path(@page, version_id: @screenshot.id, viewport: :mobile)

    assert_response :success
    assert_select "[data-testid='viewport-switcher-mobile'][aria-selected='true']"
  end

  test "show at /viewports/:viewport silently falls back to default when viewport is missing" do
    sign_in(@user)
    assert_equal %w[desktop], @screenshot.available_viewports

    get page_path(@page, version_id: @screenshot.id, viewport: :mobile)

    assert_response :success
    assert_select ".screenshot-workspace"
    assert_select "[data-testid='viewport-switcher-desktop'][aria-selected='true']", count: 0
  end

  test "annotation form carries the active viewport so drawn annotations stick to it" do
    sign_in(@user)
    @screenshot.screenshot_images.create!(viewport: :mobile)

    get page_path(@page, version_id: @screenshot.id, viewport: :mobile)

    assert_response :success
    # Hidden field inside the annotation form should carry mobile so new
    # annotations drawn on this view save as :mobile, not the model default.
    assert_select "input[type=hidden][name='annotation[viewport]'][value='mobile']"
  end

  test "status filters preserve the active viewport" do
    sign_in(@user)
    @screenshot.screenshot_images.create!(viewport: :mobile)

    get page_path(@page, version_id: @screenshot.id, viewport: :mobile)

    assert_response :success
    # Filter links should point at the same viewport, not fall back to default.
    assert_select "a.annotation-filter[href='#{page_path(@page, version_id: @screenshot.id, viewport: :mobile, status: :open)}']"
    assert_select "a.annotation-filter[href='#{page_path(@page, version_id: @screenshot.id, viewport: :mobile, status: :resolved)}']"
  end

  test "viewport switcher lives inside the turbo frame so active state re-renders on nav" do
    sign_in(@user)
    @screenshot.screenshot_images.create!(viewport: :mobile)

    get page_path(@page, version_id: @screenshot.id)

    assert_response :success
    # Frame must contain the switcher so a viewport click re-renders the
    # active-button highlight along with the canvas + sidebar.
    assert_select "turbo-frame#screenshot_canvas .viewport-switcher"
  end

  test "show scopes annotations to the active viewport" do
    sign_in(@user)
    @screenshot.screenshot_images.create!(viewport: :mobile)
    annotations(:point_annotation).update!(viewport: :mobile)

    get page_path(@page, version_id: @screenshot.id, viewport: :desktop)

    # Mobile annotation should NOT appear on desktop
    assert_select "[data-annotation-id='#{annotations(:point_annotation).id}']", 0
  end

  # New
  test "new renders form" do
    sign_in(@user)
    get new_page_screenshot_path(@page)
    assert_response :success
    assert_select "form"
  end

  # Create
  test "create with valid params" do
    sign_in(@user)
    image = fixture_file_upload("test_image.png", "image/png")

    assert_difference "Screenshot.count", 1 do
      post page_screenshots_path(@page), params: { screenshot: { title: "New Screenshot", image: image } }
    end

    screenshot = Screenshot.last
    assert_redirected_to page_path(@page, version_id: screenshot.id)
    assert_equal "New Screenshot", screenshot.title
    assert screenshot.primary_image.image.attached?, "Image should be attached to the desktop ScreenshotImage"
  end

  test "create with an image schedules dimension processing immediately" do
    sign_in(@user)
    image = fixture_file_upload("test_image.png", "image/png")

    assert_enqueued_jobs 1, only: ScreenshotDimensionJob do
      post page_screenshots_path(@page), params: { screenshot: { title: "Process me", image: image } }
    end

    screenshot_image = Screenshot.last.primary_image
    assert_enqueued_with(job: ScreenshotDimensionJob, args: [ screenshot_image, screenshot_image.image.blob.id ])
  end

  test "create without image still creates screenshot" do
    sign_in(@user)

    assert_difference "Screenshot.count", 1 do
      post page_screenshots_path(@page), params: { screenshot: { title: "No Image Screenshot" } }
    end

    assert_redirected_to page_path(@page, version_id: Screenshot.last.id)
  end

  test "create without image does not enqueue ScreenshotDimensionJob" do
    sign_in(@user)

    assert_no_enqueued_jobs only: ScreenshotDimensionJob do
      post page_screenshots_path(@page), params: { screenshot: { title: "No Image Screenshot" } }
    end
  end

  test "create with invalid params renders form" do
    sign_in(@user)

    assert_no_difference "Screenshot.count" do
      post page_screenshots_path(@page), params: { screenshot: { title: "" } }
    end
    assert_response :unprocessable_entity
  end

  # Edit
  test "edit renders form" do
    sign_in(@user)
    get edit_screenshot_path(@screenshot)
    assert_response :success
    assert_select "form"
  end

  # Update
  test "update with valid params" do
    sign_in(@user)
    patch screenshot_path(@screenshot), params: { screenshot: { title: "Updated Title" } }
    assert_redirected_to page_path(@page, version_id: @screenshot.id)
    assert_equal "Updated Title", @screenshot.reload.title
  end

  test "update with invalid params renders form" do
    sign_in(@user)
    patch screenshot_path(@screenshot), params: { screenshot: { title: "" } }
    assert_response :unprocessable_entity
  end

  test "create surfaces ScreenshotImage validation errors on the form" do
    sign_in(@user)
    # GIF is not in ALLOWED_CONTENT_TYPES — ScreenshotImage#acceptable_image fails.
    gif = fixture_file_upload("test_invalid.gif", "image/gif")

    post page_screenshots_path(@page), params: { screenshot: { title: "GIF upload", image: gif } }

    assert_response :unprocessable_entity
    # The form must re-render with the blob-level error surfaced, otherwise the
    # user gets a 422 with no explanation.
    assert_select ".form__errors"
    assert_match(/PNG or JPEG/, response.body)
  end

  test "create rejects an image whose dimensions exceed the decoder boundary" do
    sign_in(@user)
    upload, tempfile = uploaded_image(
      Vips::Image.black(ScreenshotImage::MAX_DIMENSION + 1, 1).pngsave_buffer,
      filename: "extreme.png"
    )

    assert_no_difference "Screenshot.count" do
      post page_screenshots_path(@page), params: { screenshot: { title: "Extreme", image: upload } }
    end

    assert_response :unprocessable_entity
    assert_match(/dimensions/, response.body)
  ensure
    tempfile&.close!
  end

  test "update with a replacement image routes the new blob onto primary_image" do
    sign_in(@user)
    new_image = fixture_file_upload("test_image.png", "image/png")

    # Seed: primary_image has an initial blob so we can detect replacement.
    si = @screenshot.screenshot_images.find_or_create_by(viewport: :desktop)
    si.image.attach(io: File.open(Rails.root.join("test/fixtures/files/test_image.png")),
                    filename: "old.png", content_type: "image/png")
    original_blob_id = si.image.blob.id

    patch screenshot_path(@screenshot), params: { screenshot: { image: new_image } }
    assert_redirected_to page_path(@page, version_id: @screenshot.id)

    si.reload
    assert si.image.attached?, "Primary image should still have an attachment"
    assert_not_equal original_blob_id, si.image.blob.id,
      "Replacement must land on primary_image, not on Screenshot#image (legacy)"
  end

  test "update with a replacement image enqueues a fresh ScreenshotDimensionJob" do
    sign_in(@user)
    new_image = fixture_file_upload("test_image.png", "image/png")

    patch screenshot_path(@screenshot), params: { screenshot: { image: new_image } }

    si = @screenshot.reload.primary_image
    assert_enqueued_with(job: ScreenshotDimensionJob, args: [ si, si.image.blob.id ])
  end

  test "update rejects an extreme replacement without changing the title or current blob" do
    sign_in(@user)
    screenshot_image = @screenshot.primary_image
    screenshot_image.image.attach(
      io: File.open(Rails.root.join("test/fixtures/files/test_image.png")),
      filename: "current.png",
      content_type: "image/png"
    ) unless screenshot_image.image.attached?
    original_title = @screenshot.title
    original_blob_id = screenshot_image.image.blob.id
    upload, tempfile = uploaded_image(
      Vips::Image.black(ScreenshotImage::MAX_DIMENSION + 1, 1).pngsave_buffer,
      filename: "extreme.png"
    )

    patch screenshot_path(@screenshot), params: {
      screenshot: { title: "Must roll back", image: upload }
    }

    assert_response :unprocessable_entity
    assert_equal original_title, @screenshot.reload.title
    assert_equal original_blob_id, screenshot_image.reload.image.blob.id
    assert_match(/dimensions/, response.body)
  ensure
    tempfile&.close!
  end

  # Destroy
  test "destroying the last screenshot also deletes its empty page" do
    sign_in(@user)

    assert_difference -> { Screenshot.count }, -1 do
      assert_difference -> { Page.count }, -1 do
        delete screenshot_path(@screenshot)
      end
    end
    assert_redirected_to project_path(@project)
    assert_equal "Last version deleted. Page removed.", flash[:notice]
  end

  test "destroying one of several screenshots keeps the page and selects a remaining version" do
    sign_in(@user)
    remaining_screenshot = @page.screenshots.create!(title: "Remaining version", status: :ready)

    assert_difference -> { Screenshot.count }, -1 do
      assert_no_difference -> { Page.count } do
        delete screenshot_path(@screenshot)
      end
    end

    assert_redirected_to page_path(@page, version_id: remaining_screenshot.id)
    assert_equal "Screenshot deleted.", flash[:notice]
  end

  test "destroy returns not found without changing another users screenshot or page" do
    sign_in(@user)
    screenshot = screenshots(:bob_screenshot)
    page = screenshot.page

    assert_no_difference -> { Screenshot.count } do
      assert_no_difference -> { Page.count } do
        delete screenshot_path(screenshot)
      end
    end

    assert_response :not_found
    assert Screenshot.exists?(screenshot.id)
    assert Page.exists?(page.id)
  end

  private

  def uploaded_image(bytes, filename:, content_type: "image/png")
    tempfile = Tempfile.new([ "screenote-controller-test", File.extname(filename) ])
    tempfile.binmode
    tempfile.write(bytes)
    tempfile.rewind
    upload = Rack::Test::UploadedFile.new(tempfile.path, content_type, true, original_filename: filename)
    [ upload, tempfile ]
  end
end
