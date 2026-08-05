# frozen_string_literal: true

class RemoveProjectMemberTool < ApplicationTool
  tool_name "remove_project_member"
  description "Remove a member from a project. Cannot remove yourself or the sole owner. Requires owner role."
  mcp_action scope: :mcp_write, read_only: false, destructive: true, idempotent: false, open_world: false
  authorize { current_user.present? }

  arguments do
    required(:project_id).filled(:integer).description("The project ID")
    required(:membership_id).filled(:integer).description("The membership ID to remove")
  end

  def call(project_id:, membership_id:)
    error = require_project(project_id)
    return error if error

    with_error_handling do
      result = ProjectMemberships::Remove.call(
        project: current_project,
        membership_id: membership_id,
        actor: current_user
      )

      case result.status
      when :removed
        { success: true, message: "#{result.membership.user.email} removed from project" }.to_json
      when :cannot_remove_self
        { error: "cannot_remove_self", message: "You cannot remove yourself from the project" }.to_json
      when :forbidden
        { error: "forbidden", message: "Only project owners can remove members" }.to_json
      when :not_found
        { error: "not_found", message: "Project membership not found" }.to_json
      when :invalid
        { error: "validation_failed", message: result.membership.errors.full_messages.to_sentence }.to_json
      end
    end
  end
end
