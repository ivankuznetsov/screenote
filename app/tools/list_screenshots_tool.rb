# frozen_string_literal: true

class ListScreenshotsTool < ApplicationTool
  tool_name "list_screenshots"
  description "List screenshots in the project, with annotation counts. Supports pagination via limit/offset."

  arguments do
    optional(:status).filled(:string).description("Filter by status: pending, ready, or failed")
    optional(:limit).filled(:integer).description("Max results to return (default 50, max 100)")
    optional(:offset).filled(:integer).description("Number of results to skip (default 0)")
  end

  def call(status: nil, limit: 50, offset: 0)
    with_error_handling do
      limit = limit.to_i.clamp(1, 100)
      offset = [ offset.to_i, 0 ].max

      screenshots = current_project.screenshots.order(created_at: :desc)
      screenshots = screenshots.where(status: status) if status.present?

      total = screenshots.count
      screenshots = screenshots.limit(limit).offset(offset)

      {
        screenshots: screenshots.map do |s|
          url = Rails.application.routes.url_helpers.project_screenshot_url(current_project, s)

          {
            id: s.id,
            title: s.title,
            status: s.status,
            annotation_count: s.annotations.count,
            unresolved_count: s.annotations.open.count,
            annotate_url: url,
            created_at: s.created_at.iso8601
          }
        end,
        pagination: { total: total, limit: limit, offset: offset }
      }.to_json
    end
  end
end
