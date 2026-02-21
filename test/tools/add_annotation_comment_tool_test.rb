# frozen_string_literal: true

require "test_helper"

class AddAnnotationCommentToolTest < ActiveSupport::TestCase
  setup do
    @user = users(:alice)
    @project = projects(:alice_project)
    @api_key = api_keys(:alice_key)
    @annotation = annotations(:point_annotation)

    Current.mcp_user = @user
    Current.mcp_project = @project
    Current.mcp_api_key = @api_key
  end

  teardown do
    Current.reset
  end

  test "adds a comment to an annotation" do
    result = JSON.parse(AddAnnotationCommentTool.new.call(
      project_id: @project.id,
      annotation_id: @annotation.id,
      body: "Looking into this issue now"
    ))

    assert result["success"], "Should return success"
    assert result["comment"]["id"].present?, "Should return comment ID"
    assert_equal @annotation.id, result["comment"]["annotation_id"]
    assert_equal "comment", result["comment"]["action"]
    assert_equal "Looking into this issue now", result["comment"]["body"]
    assert_equal @api_key.name, result["comment"]["author"]
    assert result["comment"]["created_at"].present?, "Should include created_at timestamp"
  end

  test "comment is attributed to the API key" do
    assert_difference "AnnotationComment.count", 1 do
      AddAnnotationCommentTool.new.call(
        project_id: @project.id,
        annotation_id: @annotation.id,
        body: "Agent status update"
      )
    end

    comment = AnnotationComment.last
    assert_equal @api_key.id, comment.api_key_id, "Comment should be attributed to the API key"
    assert_nil comment.user_id, "Comment should not have a user author"
    assert_equal "comment", comment.action, "Action should be comment"
  end

  test "returns not_found for another project's annotation" do
    bob_annotation = annotations(:bob_annotation)

    result = JSON.parse(AddAnnotationCommentTool.new.call(
      project_id: @project.id,
      annotation_id: bob_annotation.id,
      body: "Should not work"
    ))

    assert_equal "not_found", result["error"], "Should return not_found for other project's annotation"
  end

  test "returns validation_failed for empty body" do
    result = JSON.parse(AddAnnotationCommentTool.new.call(
      project_id: @project.id,
      annotation_id: @annotation.id,
      body: ""
    ))

    assert_equal "validation_failed", result["error"], "Should return validation error for empty body"
  end
end
