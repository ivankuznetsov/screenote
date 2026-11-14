# frozen_string_literal: true

class ListPagesTool < ApplicationTool
  tool_name "list_pages"
  description "List pages in a project with version counts."
  mcp_action scope: :mcp_read, read_only: true, destructive: false, idempotent: true, open_world: false

  arguments do
    required(:project_id).filled(:integer).description("The project ID")
  end

  def call(project_id:)
    error = require_project(project_id)
    return error if error

    with_error_handling do
      {
        pages: Api::V1::ProjectScope.pages(current_project).map do |page|
          Api::V1::ContractSerializer.page(page, url_options: serializer_url_options)
        end
      }.to_json
    end
  end
end
