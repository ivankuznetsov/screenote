# frozen_string_literal: true

class ListAnnotationsTool < ApplicationTool
  tool_name "list_annotations"
  description "List annotations, optionally filtered by screenshot or status. Supports pagination via limit/offset."

  arguments do
    optional(:screenshot_id).filled(:integer).description("Filter by screenshot ID")
    optional(:status).filled(:string).description("Filter by status: open or resolved")
    optional(:limit).filled(:integer).description("Max results to return (default 50, max 100)")
    optional(:offset).filled(:integer).description("Number of results to skip (default 0)")
  end

  def call(screenshot_id: nil, status: nil, limit: 50, offset: 0)
    with_error_handling do
      limit = limit.to_i.clamp(1, 100)
      offset = [ offset.to_i, 0 ].max

      annotations = Annotation.joins(screenshot: :project)
        .where(projects: { id: current_project.id })
        .includes(:user, :screenshot)
        .order(:created_at)

      annotations = annotations.where(screenshot_id: screenshot_id) if screenshot_id
      annotations = annotations.where(status: status) if status.present?

      total = annotations.count
      annotations = annotations.limit(limit).offset(offset)

      {
        annotations: annotations.map do |a|
          {
            id: a.id,
            screenshot_id: a.screenshot_id,
            type: a.point? ? "point" : "region",
            coordinates: {
              x_percent: a.x_percent,
              y_percent: a.y_percent,
              width_percent: a.width_percent,
              height_percent: a.height_percent
            },
            comment: a.comment,
            status: a.status,
            author: a.user.email,
            created_at: a.created_at.iso8601
          }
        end,
        pagination: { total: total, limit: limit, offset: offset }
      }.to_json
    end
  end
end
