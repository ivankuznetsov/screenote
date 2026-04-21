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
  test "show displays screenshot" do
    sign_in(@user)
    get screenshot_path(@screenshot)
    assert_response :success
    assert_select ".screenshot-header__breadcrumb", /#{@screenshot.title}/
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

    assert_response :success
    assert_select ".screenshot-header__breadcrumb", /#{@screenshot.title}/
  end

  # Viewport switcher
  test "show renders viewport switcher when multiple viewports exist" do
    sign_in(@user)
    @screenshot.screenshot_images.create!(viewport: :mobile)
    @screenshot.screenshot_images.create!(viewport: :tablet)

    get screenshot_path(@screenshot)

    assert_response :success
    assert_select ".viewport-switcher"
    assert_select "[data-testid='viewport-switcher-desktop']"
    assert_select "[data-testid='viewport-switcher-tablet']"
    assert_select "[data-testid='viewport-switcher-mobile']"
  end

  test "show hides viewport switcher for single-viewport legacy screenshots" do
    sign_in(@user)
    assert_equal 1, @screenshot.screenshot_images.count

    get screenshot_path(@screenshot)

    assert_response :success
    assert_select ".viewport-switcher", 0, "No switcher when only one viewport exists"
  end

  test "show at /viewports/:viewport renders the matching variant" do
    sign_in(@user)
    @screenshot.screenshot_images.create!(viewport: :mobile)
    annotations(:point_annotation).update!(viewport: :mobile)

    get viewport_screenshot_path(@screenshot, :mobile)

    assert_response :success
    assert_select "[data-testid='viewport-switcher-mobile'][aria-selected='true']"
  end

  test "show at /viewports/:viewport silently falls back to default when viewport is missing" do
    sign_in(@user)
    assert_equal %w[desktop], @screenshot.available_viewports

    get viewport_screenshot_path(@screenshot, :mobile)

    # No redirect, no flash — the canonical /screenshots/:id would show the same
    # desktop canvas. Silent fallback > jarring redirect for a URL no human typed.
    assert_response :success
    assert_select ".screenshot-workspace"
  end

  test "show scopes annotations to the active viewport" do
    sign_in(@user)
    @screenshot.screenshot_images.create!(viewport: :mobile)
    annotations(:point_annotation).update!(viewport: :mobile)

    get viewport_screenshot_path(@screenshot, :desktop)

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
    assert_redirected_to screenshot_path(screenshot)
    assert_equal "New Screenshot", screenshot.title
    assert screenshot.primary_image.image.attached?, "Image should be attached to the desktop ScreenshotImage"
  end

  test "create without image still creates screenshot" do
    sign_in(@user)

    assert_difference "Screenshot.count", 1 do
      post page_screenshots_path(@page), params: { screenshot: { title: "No Image Screenshot" } }
    end

    assert_redirected_to screenshot_path(Screenshot.last)
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
    assert_redirected_to screenshot_path(@screenshot)
    assert_equal "Updated Title", @screenshot.reload.title
  end

  test "update with invalid params renders form" do
    sign_in(@user)
    patch screenshot_path(@screenshot), params: { screenshot: { title: "" } }
    assert_response :unprocessable_entity
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
    assert_redirected_to screenshot_path(@screenshot)

    si.reload
    assert si.image.attached?, "Primary image should still have an attachment"
    assert_not_equal original_blob_id, si.image.blob.id,
      "Replacement must land on primary_image, not on Screenshot#image (legacy)"
  end

  test "update with a replacement image enqueues a fresh ScreenshotDimensionJob" do
    sign_in(@user)
    new_image = fixture_file_upload("test_image.png", "image/png")

    assert_enqueued_with(job: ScreenshotDimensionJob) do
      patch screenshot_path(@screenshot), params: { screenshot: { image: new_image } }
    end
  end

  # Destroy
  test "destroy deletes screenshot" do
    sign_in(@user)

    assert_difference "Screenshot.count", -1 do
      delete screenshot_path(@screenshot)
    end
    assert_redirected_to page_path(@page)
  end
end
