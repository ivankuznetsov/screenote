# frozen_string_literal: true

class ResolveAnnotationTool < ApplicationTool
  tool_name "resolve_annotation"
  description "Mark an annotation as resolved."

  arguments do
    required(:annotation_id).filled(:integer).description("The annotation ID to resolve")
  end

  def call(annotation_id:)
    with_error_handling do
      annotation = Annotation.joins(screenshot: :project)
        .where(projects: { id: current_project.id })
        .find(annotation_id)

      annotation.update!(status: :resolved, resolved_by_api_key: current_api_key)

      { success: true, annotation: { id: annotation.id, status: annotation.status } }.to_json
    end
  end
end
