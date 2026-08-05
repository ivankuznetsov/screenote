# frozen_string_literal: true

class ListProjectsTool < ApplicationTool
  tool_name "list_projects"
  description "List projects you have access to. Use the returned project_id with other tools."
  mcp_action scope: :mcp_read, read_only: true, destructive: false, idempotent: true, open_world: false

  arguments do
  end

  def call
    with_error_handling do
      {
        projects: visible_projects.filter_map { |project| serialize_visible_project(project) }
      }.to_json
    end
  end

  private

  def visible_projects
    return current_user.projects.order(:name) unless current_principal.project_principal?
    return Project.where(id: current_project.id) if current_principal.api_key?

    # The principal's project object was resolved during bearer authentication.
    # Query through memberships again so a concurrently removed OAuth member
    # cannot list a project from that stale object.
    current_user.projects.where(id: current_project.id)
  end

  def serialize_visible_project(project)
    role = current_principal.api_key? ? "api_key" : project.role_for(current_user)&.to_s
    return if role.blank?

    {
      id: project.id,
      name: project.name,
      role: role,
      screenshot_count: project.screenshots.count,
      created_at: project.created_at.iso8601
    }
  end
end
