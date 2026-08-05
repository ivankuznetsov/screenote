# frozen_string_literal: true

class ListPagesTool < ApplicationTool
  tool_name "list_pages"
  description "List pages in a project with version counts."

  arguments do
    required(:project_id).filled(:integer).description("The project ID")
  end

  def call(project_id:)
    error = require_project(project_id)
    return error if error

    with_error_handling do
      project = current_project
      pages = project.pages
        .left_joins(:screenshots)
        .select("pages.*, COUNT(screenshots.id) AS version_count")
        .group("pages.id")
        .order(:created_at)

      {
        pages: pages.map do |page|
          {
            id: page.id,
            name: page.name,
            version_count: page.version_count,
            url: Rails.application.routes.url_helpers.page_url(
              page,
              Screenote::Deployment.current.url_options
            ),
            created_at: page.created_at.iso8601
          }
        end
      }.to_json
    end
  end
end
