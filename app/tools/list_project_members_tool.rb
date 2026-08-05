# frozen_string_literal: true

class ListProjectMembersTool < ApplicationTool
  tool_name "list_project_members"
  description "List all members and pending invitations for a project."
  mcp_action scope: :mcp_read, read_only: true, destructive: false, idempotent: true, open_world: false

  arguments do
    required(:project_id).filled(:integer).description("The project ID")
  end

  def call(project_id:)
    error = require_project(project_id)
    return error if error

    with_error_handling do
      memberships = current_project.project_memberships.includes(:user).order(:created_at)
      pending_invitations = current_project.project_invitations.pending.order(:created_at)

      {
        members: memberships.map do |m|
          {
            membership_id: m.id,
            user_id: m.user_id,
            email: m.user.email,
            role: m.role,
            joined_at: m.created_at.iso8601
          }
        end,
        pending_invitations: pending_invitations.map do |inv|
          {
            invitation_id: inv.id,
            email: inv.email,
            invited_by: inv.inviter.email,
            created_at: inv.created_at.iso8601
          }
        end
      }.to_json
    end
  end
end
