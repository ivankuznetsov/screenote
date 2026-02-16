# frozen_string_literal: true

class ResolveAnnotationTool < ApplicationTool
  tool_name "resolve_annotation"
  description "Mark an annotation as resolved."

  arguments do
    required(:project_id).filled(:integer).description("The project ID")
    required(:annotation_id).filled(:integer).description("The annotation ID to resolve")
  end

  def call(project_id:, annotation_id:)
    error = require_project(project_id)
    return error if error

    with_error_handling do
      annotation = project_annotations(current_project).find(annotation_id)

      annotation.update!(status: :resolved)

      { success: true, annotation: { id: annotation.id, status: annotation.status } }.to_json
    end
  end
end
