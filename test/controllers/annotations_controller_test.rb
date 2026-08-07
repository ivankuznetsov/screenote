# frozen_string_literal: true

# screenote-edition: self_hosted

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
    assert_redirected_to page_path(@screenshot.page, version_id: @screenshot.id, viewport: :desktop)
    assert_equal 45.5, annotation.x_percent
    assert_equal 60.0, annotation.y_percent
    assert_nil annotation.width_percent
    assert annotation.point?, "Should be a point annotation"
    assert_equal @user, annotation.user
  end

  test "create validation failure preserves an accepted mobile viewport" do
    sign_in(@user)
    @screenshot.screenshot_images.create!(viewport: :mobile)

    assert_no_difference "Annotation.count" do
      post screenshot_annotations_path(@screenshot), params: {
        annotation: {
          x_percent: 90, y_percent: 20,
          width_percent: 20, height_percent: 20,
          comment: "Outside",
          viewport: "mobile"
        }
      }
    end

    assert_redirected_to page_path(@screenshot.page, version_id: @screenshot.id, viewport: :mobile)
  end

  test "create rejects a forged viewport without creating an annotation" do
    sign_in(@user)

    assert_no_difference "Annotation.count" do
      post screenshot_annotations_path(@screenshot), params: {
        annotation: {
          x_percent: 10, y_percent: 20,
          comment: "Forged",
          viewport: "television"
        }
      }
    end

    assert_redirected_to page_path(@screenshot.page, version_id: @screenshot.id)
    assert_equal "Could not save annotation.", flash[:alert]
  end

  test "create rejects an enum-valid viewport unavailable on the screenshot" do
    sign_in(@user)

    assert_no_difference "Annotation.count" do
      post screenshot_annotations_path(@screenshot), params: {
        annotation: { x_percent: 10, y_percent: 20, comment: "Unavailable", viewport: "mobile" }
      }
    end

    assert_redirected_to page_path(@screenshot.page, version_id: @screenshot.id)
    assert_equal "Could not save annotation.", flash[:alert]
  end

  test "create with a blank viewport preserves the model default" do
    sign_in(@user)

    assert_difference "Annotation.count", 1 do
      post screenshot_annotations_path(@screenshot), params: {
        annotation: { x_percent: 10, y_percent: 20, comment: "Default viewport", viewport: "" }
      }
    end

    assert_equal "desktop", Annotation.last.viewport
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
    @screenshot.screenshot_images.create!(viewport: :mobile)
    @annotation.update!(viewport: :mobile)

    patch screenshot_annotation_path(@screenshot, @annotation), params: {
      annotation: { status: :resolved }
    }

    assert_redirected_to page_path(@screenshot.page, version_id: @screenshot.id, viewport: :mobile)
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

  test "update with status open does not reopen resolved annotation" do
    sign_in(@user)

    # First resolve the annotation
    patch screenshot_annotation_path(@screenshot, @annotation), params: {
      annotation: { status: :resolved }
    }
    assert_equal "resolved", @annotation.reload.status

    # Try to reopen via status param (should be ignored)
    patch screenshot_annotation_path(@screenshot, @annotation), params: {
      annotation: { status: :open }
    }

    # Should still be resolved because :status is not in permitted params
    assert_equal "resolved", @annotation.reload.status
  end

  test "update annotation comment does not set resolved_by_user" do
    sign_in(@user)
    @screenshot.screenshot_images.create!(viewport: :tablet)
    @annotation.update!(viewport: :tablet)

    patch screenshot_annotation_path(@screenshot, @annotation), params: {
      annotation: { comment: "Updated comment" }
    }

    assert_redirected_to page_path(@screenshot.page, version_id: @screenshot.id, viewport: :tablet)
    assert_equal "Updated comment", @annotation.reload.comment
    assert_nil @annotation.resolved_by_user, "Should not set resolved_by_user when only updating comment"
  end

  # Destroy
  test "destroy annotation" do
    sign_in(@user)
    @screenshot.screenshot_images.create!(viewport: :mobile)
    @annotation.update!(viewport: :mobile)

    assert_difference "Annotation.count", -1 do
      delete screenshot_annotation_path(@screenshot, @annotation)
    end
    assert_redirected_to page_path(@screenshot.page, version_id: @screenshot.id, viewport: :mobile)
  end

  test "update validation failure returns to the persisted viewport" do
    sign_in(@user)
    @screenshot.screenshot_images.create!(viewport: :mobile)
    @annotation.update!(viewport: :mobile)

    patch screenshot_annotation_path(@screenshot, @annotation), params: {
      annotation: { comment: "" }
    }

    assert_redirected_to page_path(@screenshot.page, version_id: @screenshot.id, viewport: :mobile)
    assert_equal "Button text too small", @annotation.reload.comment
  end

  test "update rejects a forged viewport without changing the annotation" do
    sign_in(@user)
    original_attributes = @annotation.attributes.slice("comment", "viewport")

    patch screenshot_annotation_path(@screenshot, @annotation), params: {
      annotation: { comment: "Should not save", viewport: "television" }
    }

    assert_redirected_to page_path(@screenshot.page, version_id: @screenshot.id, viewport: :desktop)
    assert_equal original_attributes, @annotation.reload.attributes.slice("comment", "viewport")
  end

  test "update rejects an enum-valid viewport unavailable on the screenshot" do
    sign_in(@user)
    original_attributes = @annotation.attributes.slice("comment", "viewport")

    patch screenshot_annotation_path(@screenshot, @annotation), params: {
      annotation: { comment: "Should not save", viewport: "mobile" }
    }

    assert_redirected_to page_path(@screenshot.page, version_id: @screenshot.id, viewport: :desktop)
    assert_equal original_attributes, @annotation.reload.attributes.slice("comment", "viewport")
  end

  test "update with a blank viewport preserves the annotation viewport" do
    sign_in(@user)
    @screenshot.screenshot_images.create!(viewport: :mobile)
    @annotation.update!(viewport: :mobile)

    patch screenshot_annotation_path(@screenshot, @annotation), params: {
      annotation: { comment: "Updated comment", viewport: "" }
    }

    assert_redirected_to page_path(@screenshot.page, version_id: @screenshot.id, viewport: :mobile)
    assert_equal "mobile", @annotation.reload.viewport
    assert_equal "Updated comment", @annotation.comment
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
