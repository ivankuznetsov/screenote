# frozen_string_literal: true

class ListScreenshotsTool < ApplicationTool
  tool_name "list_screenshots"
  description "List screenshots (versions) in a project, with annotation counts. Supports filtering by page and pagination via limit/offset."
  mcp_action scope: :mcp_read, read_only: true, destructive: false, idempotent: true, open_world: false

  arguments do
    required(:project_id).filled(:integer).description("The project ID")
    optional(:page_id).filled(:integer).description("Filter by page ID")
    optional(:status).filled(:string).description("Filter by status: pending, ready, or failed")
    optional(:limit).filled(:integer).description("Max results to return (default 50, max 100)")
    optional(:offset).filled(:integer).description("Number of results to skip (default 0)")
  end

  def call(project_id:, page_id: nil, status: nil, limit: 50, offset: 0)
    error = require_project(project_id) || invalid_enum_filter("status", status, Screenshot.statuses)
    return error if error

    with_error_handling do
      limit = limit.to_i.clamp(1, 100)
      offset = [ offset.to_i, 0 ].max

      screenshots = Api::V1::ProjectScope.screenshots(current_project)
      screenshots = screenshots.where(page_id: page_id) if page_id.present?
      screenshots = screenshots.where(status: status) if status.present?

      total = screenshots.count
      screenshots = screenshots.limit(limit).offset(offset)

      {
        screenshots: Api::V1::ContractSerializer.screenshots(screenshots, url_options: serializer_url_options),
        pagination: { total: total, limit: limit, offset: offset }
      }.to_json
    end
  end
end
