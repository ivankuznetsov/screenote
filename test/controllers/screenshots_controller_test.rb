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

  # Destroy
  test "destroy deletes screenshot" do
    sign_in(@user)

    assert_difference "Screenshot.count", -1 do
      delete screenshot_path(@screenshot)
    end
    assert_redirected_to page_path(@page)
  end
end
