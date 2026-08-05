# frozen_string_literal: true

class AddAnnotationCommentTool < ApplicationTool
  tool_name "add_annotation_comment"
  description "Add a comment to an annotation thread to ask questions, provide status updates, or add context."
  mcp_action scope: :mcp_write, read_only: false, destructive: false, idempotent: false, open_world: false

  arguments do
    required(:project_id).filled(:integer).description("The project ID")
    required(:annotation_id).filled(:integer).description("The ID of the annotation to comment on")
    required(:body).filled(:string).description("The comment text")
  end

  def call(project_id:, annotation_id:, body:)
    error = require_project(project_id)
    return error if error

    with_error_handling do
      annotation = project_annotations(current_project).find(annotation_id)
      comment = annotation.annotation_comments.create!(
        **current_actor_attributes,
        body: body,
        action: :comment
      )

      {
        success: true,
        comment: {
          id: comment.id,
          annotation_id: annotation.id,
          action: comment.action,
          body: comment.body,
          author: current_user&.email || current_principal.api_key&.name,
          created_at: comment.created_at.iso8601
        }
      }.to_json
    end
  end
end
