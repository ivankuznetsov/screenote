# frozen_string_literal: true

class ListProjectsTool < ApplicationTool
  tool_name "list_projects"
  description "List projects you have access to. Use the returned project_id with other tools."
  mcp_action scope: :mcp_read, read_only: true, destructive: false, idempotent: true, open_world: false

  arguments do
  end

  def call
    with_error_handling do
      roles = visible_project_roles
      screenshot_counts = Api::V1::ProjectScope.screenshot_counts(roles.map { |project, _role| project.id })

      {
        projects: roles.map do |project, role|
          Api::V1::ContractSerializer.project(
            project,
            screenshot_count: screenshot_counts.fetch(project.id, 0)
          ).merge(role: role)
        end
      }.to_json
    end
  end

  private

  # [project, role] pairs ordered by project name.
  def visible_project_roles
    if current_principal.api_key?
      return Project.where(id: current_project.id).map { |project| [ project, "api_key" ] }
    end

    # The principal's project object was resolved during bearer authentication.
    # Roles come from a fresh membership query so a concurrently removed OAuth
    # member cannot list a project from that stale object.
    Api::V1::ProjectScope.memberships(current_principal)
      .joins(:project)
      .merge(Project.order(:name))
      .map { |membership| [ membership.project, membership.role ] }
  end
end
