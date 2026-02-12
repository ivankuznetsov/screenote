# frozen_string_literal: true

class ListAnnotationsTool < ApplicationTool
  tool_name "list_annotations"
  description "List annotations, optionally filtered by screenshot or status."

  arguments do
    optional(:screenshot_id).filled(:integer).description("Filter by screenshot ID")
    optional(:status).filled(:string).description("Filter by status: open or resolved")
  end

  def call(screenshot_id: nil, status: nil)
    with_error_handling do
      annotations = Annotation.joins(screenshot: :project)
        .where(projects: { id: current_project.id })
        .includes(:user, :screenshot)
        .order(:created_at)

      annotations = annotations.where(screenshot_id: screenshot_id) if screenshot_id
      annotations = annotations.where(status: status) if status.present?

      annotations.map do |a|
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
      end.to_json
    end
  end
end
