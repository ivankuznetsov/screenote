# frozen_string_literal: true

class CreateProjectTool < ApplicationTool
  tool_name "create_project"
  description "Create a new project. Returns the project_id to use with other tools."
  mcp_action scope: :mcp_write, read_only: false, destructive: false, idempotent: false, open_world: false
  authorize { current_principal&.can_create_project? }

  arguments do
    required(:name).filled(:string).description("Name for the new project")
  end

  def call(name:)
    with_error_handling do
      project = Projects::Create.call(
        principal: current_principal,
        attributes: { name: name }
      )

      {
        project: {
          id: project.id,
          name: project.name,
          role: "owner",
          created_at: project.created_at.iso8601
        }
      }.to_json
    end
  end
end
