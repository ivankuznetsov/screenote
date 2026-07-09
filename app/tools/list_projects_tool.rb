# frozen_string_literal: true

class ListProjectsTool < ApplicationTool
  tool_name "list_projects"
  description "List projects you have access to. Use the returned project_id with other tools."

  arguments do
  end

  def call
    with_error_handling do
      projects =
        if project_scoped_oauth?
          Project.where(id: current_project.id)
        else
          current_user.projects.order(:name)
        end

      {
        projects: projects.map do |p|
          {
            id: p.id,
            name: p.name,
            role: p.role_for(current_user).to_s,
            screenshot_count: p.screenshots.count,
            created_at: p.created_at.iso8601
          }
        end
      }.to_json
    end
  end
end
