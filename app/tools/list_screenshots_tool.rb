# frozen_string_literal: true

class ListScreenshotsTool < ApplicationTool
  tool_name "list_screenshots"
  description "List all screenshots in the project, with annotation counts."

  arguments do
    optional(:status).filled(:string).description("Filter by status: pending, ready, or failed")
  end

  def call(status: nil)
    screenshots = current_project.screenshots.order(created_at: :desc)
    screenshots = screenshots.where(status: status) if status.present?

    screenshots.map do |s|
      url = Rails.application.routes.url_helpers.project_screenshot_url(
        current_project, s, host: ENV.fetch("APP_HOST", "localhost:3005")
      )

      {
        id: s.id,
        title: s.title,
        status: s.status,
        annotation_count: s.annotations.count,
        unresolved_count: s.annotations.open.count,
        annotate_url: url,
        created_at: s.created_at.iso8601
      }
    end.to_json
  end
end
