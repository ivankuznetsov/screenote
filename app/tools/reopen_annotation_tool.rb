# frozen_string_literal: true

class ReopenAnnotationTool < ApplicationTool
  tool_name "reopen_annotation"
  description "Reopen a previously resolved annotation with an explanation of why it needs more work"

  arguments do
    required(:project_id).filled(:integer).description("The project ID")
    required(:annotation_id).filled(:integer).description("The ID of the annotation to reopen")
    required(:reason).filled(:string).description("Explanation of why this annotation is being reopened")
  end

  def call(project_id:, annotation_id:, reason:)
    error = require_project(project_id)
    return error if error

    with_error_handling do
      annotation = project_annotations(current_project).find(annotation_id)
      annotation.reopen!(api_key: Current.mcp_api_key, body: reason)

      { success: true, annotation: { id: annotation.id, status: annotation.status } }.to_json
    end
  end
end
