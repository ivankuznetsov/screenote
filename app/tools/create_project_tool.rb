# frozen_string_literal: true

class CreateProjectTool < ApplicationTool
  tool_name "create_project"
  description "Create a new project. Returns the project_id to use with other tools."

  arguments do
    required(:name).filled(:string).description("Name for the new project")
  end

  def call(name:)
    with_error_handling do
      if project_scoped_oauth?
        return { error: "forbidden", message: "Project-scoped tokens cannot create projects" }.to_json
      end

      project = current_user.owned_projects.create!(name: name)

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
