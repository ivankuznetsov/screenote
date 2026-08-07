# frozen_string_literal: true

require "test_helper"

class ReopenAnnotationToolTest < ActiveSupport::TestCase
  setup do
    @user = users(:alice)
    @project = projects(:alice_project)
    @resolved_annotation = annotations(:resolved_annotation)

    Current.authenticated_principal = AuthenticatedPrincipal.for_user(@user)
  end

  teardown do
    Current.reset
  end

  test "reopens a resolved annotation" do
    result = JSON.parse(ReopenAnnotationTool.new.call(
      project_id: @project.id,
      annotation_id: @resolved_annotation.id,
      reason: "The alignment is still off on mobile"
    ))

    assert result["success"], "Should return success"
    assert_equal "open", result["annotation"]["status"]
    assert_equal "open", @resolved_annotation.reload.status, "Annotation should be open in the database"
  end

  test "creates a reopened comment attributed to the user" do
    assert_difference -> { @resolved_annotation.annotation_comments.count }, 1 do
      ReopenAnnotationTool.new.call(
        project_id: @project.id,
        annotation_id: @resolved_annotation.id,
        reason: "Still broken on Safari"
      )
    end

    comment = @resolved_annotation.annotation_comments.last
    assert_equal "reopened", comment.action, "Comment action should be reopened"
    assert_equal "Still broken on Safari", comment.body
    assert_equal @user.id, comment.user_id, "Comment should be attributed to the user"
    assert_nil comment.api_key_id, "Comment should not have an API key"
  end

  test "returns error when annotation is already open" do
    open_annotation = annotations(:point_annotation)

    result = JSON.parse(ReopenAnnotationTool.new.call(
      project_id: @project.id,
      annotation_id: open_annotation.id,
      reason: "Trying to reopen an open annotation"
    ))

    assert_equal "not_found", result["error"], "Should return not_found for already-open annotation"
  end

  test "returns not_found for another projects annotation" do
    result = JSON.parse(ReopenAnnotationTool.new.call(
      project_id: @project.id,
      annotation_id: annotations(:bob_annotation).id,
      reason: "Should not be accessible"
    ))

    assert_equal "not_found", result["error"], "Should return not_found for other project's annotation"
  end
end
