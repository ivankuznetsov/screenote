# frozen_string_literal: true

require "test_helper"

class AnnotationsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:alice)
    @project = projects(:alice_project)
    @screenshot = screenshots(:alice_screenshot)
    @annotation = annotations(:point_annotation)
  end

  # Authentication
  test "redirects to sign in when not authenticated" do
    post screenshot_annotations_path(@screenshot)
    assert_redirected_to new_session_path
  end

  # Create
  test "create point annotation" do
    sign_in(@user)

    assert_difference "Annotation.count", 1 do
      post screenshot_annotations_path(@screenshot), params: {
        annotation: { x_percent: 45.5, y_percent: 60.0, comment: "New point annotation" }
      }
    end

    annotation = Annotation.last
    assert_redirected_to screenshot_path(@screenshot)
    assert_equal 45.5, annotation.x_percent
    assert_equal 60.0, annotation.y_percent
    assert_nil annotation.width_percent
    assert annotation.point?, "Should be a point annotation"
    assert_equal @user, annotation.user
  end

  test "create region annotation" do
    sign_in(@user)

    assert_difference "Annotation.count", 1 do
      post screenshot_annotations_path(@screenshot), params: {
        annotation: {
          x_percent: 10.0, y_percent: 20.0,
          width_percent: 30.0, height_percent: 25.0,
          comment: "Region annotation"
        }
      }
    end

    annotation = Annotation.last
    assert_equal 30.0, annotation.width_percent
    assert_equal 25.0, annotation.height_percent
    assert_not annotation.point?, "Should be a region annotation"
  end

  test "create annotation on other users project returns not found" do
    sign_in(@user)

    assert_no_difference "Annotation.count" do
      post screenshot_annotations_path(screenshots(:bob_screenshot)), params: {
        annotation: { x_percent: 50.0, y_percent: 50.0, comment: "Unauthorized" }
      }
    end
    assert_response :not_found
  end

  # Update
  test "update annotation status to resolved" do
    sign_in(@user)

    patch screenshot_annotation_path(@screenshot, @annotation), params: {
      annotation: { status: :resolved }
    }

    assert_redirected_to screenshot_path(@screenshot)
    assert_equal "resolved", @annotation.reload.status
  end

  test "update annotation status to resolved sets resolved_by_user" do
    sign_in(@user)

    patch screenshot_annotation_path(@screenshot, @annotation), params: {
      annotation: { status: :resolved }
    }

    @annotation.reload
    assert_equal @user, @annotation.resolved_by_user, "Should record who resolved the annotation"
  end

  test "resolving annotation creates a resolved comment" do
    sign_in(@user)

    assert_difference "AnnotationComment.count", 1 do
      patch screenshot_annotation_path(@screenshot, @annotation), params: {
        annotation: { status: :resolved }
      }
    end

    comment = @annotation.annotation_comments.last
    assert_equal "resolved", comment.action
    assert_equal @user, comment.user
  end

  test "update annotation comment does not set resolved_by_user" do
    sign_in(@user)

    patch screenshot_annotation_path(@screenshot, @annotation), params: {
      annotation: { comment: "Updated comment" }
    }

    assert_redirected_to screenshot_path(@screenshot)
    assert_equal "Updated comment", @annotation.reload.comment
    assert_nil @annotation.resolved_by_user, "Should not set resolved_by_user when only updating comment"
  end

  # Destroy
  test "destroy annotation" do
    sign_in(@user)

    assert_difference "Annotation.count", -1 do
      delete screenshot_annotation_path(@screenshot, @annotation)
    end
    assert_redirected_to screenshot_path(@screenshot)
  end

  test "destroy annotation on other users project returns not found" do
    sign_in(@user)

    assert_no_difference "Annotation.count" do
      delete screenshot_annotation_path(
        screenshots(:bob_screenshot),
        annotations(:bob_annotation)
      )
    end
    assert_response :not_found
  end
end
