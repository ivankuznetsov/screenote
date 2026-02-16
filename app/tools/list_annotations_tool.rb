# frozen_string_literal: true

class ListAnnotationsTool < ApplicationTool
  tool_name "list_annotations"
  description "List annotations, optionally filtered by screenshot or status. Supports pagination via limit/offset."

  arguments do
    required(:project_id).filled(:integer).description("The project ID")
    optional(:screenshot_id).filled(:integer).description("Filter by screenshot ID")
    optional(:status).filled(:string).description("Filter by status: open or resolved")
    optional(:limit).filled(:integer).description("Max results to return (default 50, max 100)")
    optional(:offset).filled(:integer).description("Number of results to skip (default 0)")
  end

  def call(project_id:, screenshot_id: nil, status: nil, limit: 50, offset: 0)
    error = require_project(project_id)
    return error if error

    with_error_handling do
      limit = limit.to_i.clamp(1, 100)
      offset = [ offset.to_i, 0 ].max

      annotations = project_annotations(current_project).order(:created_at)
      annotations = annotations.where(screenshot_id: screenshot_id) if screenshot_id
      annotations = annotations.where(status: status) if status.present?

      total = annotations.count
      annotations = annotations.limit(limit).offset(offset)

      {
        annotations: annotations.map { |a| serialize_annotation(a) },
        pagination: { total: total, limit: limit, offset: offset }
      }.to_json
    end
  end
end
