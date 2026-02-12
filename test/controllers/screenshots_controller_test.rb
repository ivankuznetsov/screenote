# frozen_string_literal: true

require "test_helper"

class ScreenshotsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:alice)
    @project = projects(:alice_project)
    @screenshot = screenshots(:alice_screenshot)
  end

  # Authentication
  test "redirects to sign in when not authenticated" do
    get project_screenshots_path(@project)
    assert_redirected_to new_session_path
  end

  # Index
  test "index shows project screenshots" do
    sign_in(@user)
    get project_screenshots_path(@project)
    assert_response :success
    assert_select ".screenshot-card__title", @screenshot.title
  end

  test "index does not show other users screenshots" do
    sign_in(@user)
    get project_screenshots_path(@project)
    assert_response :success
    assert_select ".screenshot-card__title", { text: screenshots(:bob_screenshot).title, count: 0 }
  end

  # Show
  test "show displays screenshot" do
    sign_in(@user)
    get project_screenshot_path(@project, @screenshot)
    assert_response :success
    assert_select ".screenshot-header__breadcrumb", /#{@screenshot.title}/
  end

  test "show returns not found for other users screenshot" do
    sign_in(@user)
    get project_screenshot_path(projects(:bob_project), screenshots(:bob_screenshot))
    assert_response :not_found
  end

  # New
  test "new renders form" do
    sign_in(@user)
    get new_project_screenshot_path(@project)
    assert_response :success
    assert_select "form"
  end

  # Create
  test "create with valid params" do
    sign_in(@user)
    image = fixture_file_upload("test_image.png", "image/png")

    assert_difference "Screenshot.count", 1 do
      post project_screenshots_path(@project), params: { screenshot: { title: "New Screenshot", image: image } }
    end

    screenshot = Screenshot.last
    assert_redirected_to project_screenshot_path(@project, screenshot)
    assert_equal "New Screenshot", screenshot.title
    assert screenshot.image.attached?, "Image should be attached"
  end

  test "create without image still creates screenshot" do
    sign_in(@user)

    assert_difference "Screenshot.count", 1 do
      post project_screenshots_path(@project), params: { screenshot: { title: "No Image Screenshot" } }
    end

    assert_redirected_to project_screenshot_path(@project, Screenshot.last)
  end

  test "create with invalid params renders form" do
    sign_in(@user)

    assert_no_difference "Screenshot.count" do
      post project_screenshots_path(@project), params: { screenshot: { title: "" } }
    end
    assert_response :unprocessable_entity
  end

  # Edit
  test "edit renders form" do
    sign_in(@user)
    get edit_project_screenshot_path(@project, @screenshot)
    assert_response :success
    assert_select "form"
  end

  # Update
  test "update with valid params" do
    sign_in(@user)
    patch project_screenshot_path(@project, @screenshot), params: { screenshot: { title: "Updated Title" } }
    assert_redirected_to project_screenshot_path(@project, @screenshot)
    assert_equal "Updated Title", @screenshot.reload.title
  end

  test "update with invalid params renders form" do
    sign_in(@user)
    patch project_screenshot_path(@project, @screenshot), params: { screenshot: { title: "" } }
    assert_response :unprocessable_entity
  end

  # Destroy
  test "destroy deletes screenshot" do
    sign_in(@user)

    assert_difference "Screenshot.count", -1 do
      delete project_screenshot_path(@project, @screenshot)
    end
    assert_redirected_to project_screenshots_path(@project)
  end
end
