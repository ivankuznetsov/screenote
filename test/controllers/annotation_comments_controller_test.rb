# frozen_string_literal: true

require "test_helper"

class AnnotationCommentsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:alice)
    @project = projects(:alice_project)
    @screenshot = screenshots(:alice_screenshot)
    @annotation = annotations(:point_annotation)
    @resolved_annotation = annotations(:resolved_annotation)
  end

  test "redirects to sign in when not authenticated" do
    post screenshot_annotation_annotation_comments_path(
      @screenshot, @annotation
    )
    assert_redirected_to new_session_path
  end

  test "reopen annotation with comment" do
    sign_in(@user)
    @screenshot.screenshot_images.create!(viewport: :tablet)
    @resolved_annotation.update!(viewport: :tablet)

    assert_difference "AnnotationComment.count", 1 do
      post screenshot_annotation_annotation_comments_path(
        @screenshot, @resolved_annotation
      ), params: {
        annotation_comment: { body: "This is not fixed yet", reopen: "1" }
      }
    end

    assert_redirected_to page_path(@screenshot.page, version_id: @screenshot.id, viewport: :tablet)
    assert_equal "open", @resolved_annotation.reload.status
    assert_nil @resolved_annotation.resolved_by_user

    comment = @resolved_annotation.annotation_comments.last
    assert_equal "reopened", comment.action
    assert_equal "This is not fixed yet", comment.body
    assert_equal @user, comment.user
  end

  test "add plain comment to annotation" do
    sign_in(@user)
    @screenshot.screenshot_images.create!(viewport: :mobile)
    @annotation.update!(viewport: :mobile)

    assert_difference "AnnotationComment.count", 1 do
      post screenshot_annotation_annotation_comments_path(
        @screenshot, @annotation
      ), params: {
        annotation_comment: { body: "Additional feedback" }
      }
    end

    assert_redirected_to page_path(@screenshot.page, version_id: @screenshot.id, viewport: :mobile)
    assert_equal "open", @annotation.reload.status

    comment = @annotation.annotation_comments.last
    assert_equal "comment", comment.action
    assert_equal "Additional feedback", comment.body
  end

  test "reopen on already open annotation returns not found" do
    sign_in(@user)

    assert @annotation.open?
    assert_no_difference "AnnotationComment.count" do
      post screenshot_annotation_annotation_comments_path(
        @screenshot, @annotation
      ), params: {
        annotation_comment: { body: "Already open", reopen: "1" }
      }
    end
    assert_response :not_found
  end

  test "comment validation failure preserves the annotation viewport" do
    sign_in(@user)
    @screenshot.screenshot_images.create!(viewport: :mobile)
    @annotation.update!(viewport: :mobile)

    assert_no_difference "AnnotationComment.count" do
      post screenshot_annotation_annotation_comments_path(
        @screenshot, @annotation
      ), params: {
        annotation_comment: { body: "" }
      }
    end

    assert_redirected_to page_path(@screenshot.page, version_id: @screenshot.id, viewport: :mobile)
  end

  test "comment falls back to the screenshot default when persisted viewport is unavailable" do
    sign_in(@user)
    mobile = @screenshot.screenshot_images.create!(viewport: :mobile)
    @annotation.update!(viewport: :mobile)
    mobile.destroy!

    post screenshot_annotation_annotation_comments_path(
      @screenshot, @annotation
    ), params: {
      annotation_comment: { body: "Still visible on desktop" }
    }

    assert_redirected_to page_path(@screenshot.page, version_id: @screenshot.id)
  end

  test "reopen on other users project returns not found" do
    sign_in(@user)

    assert_no_difference "AnnotationComment.count" do
      post screenshot_annotation_annotation_comments_path(
        screenshots(:bob_screenshot), annotations(:bob_annotation)
      ), params: {
        annotation_comment: { body: "Not fixed", reopen: "1" }
      }
    end
    assert_response :not_found
  end
end
