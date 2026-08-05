# frozen_string_literal: true

class CancelInvitationTool < ApplicationTool
  tool_name "cancel_invitation"
  description "Cancel a pending project invitation. Requires owner role."
  mcp_action scope: :mcp_write, read_only: false, destructive: true, idempotent: false, open_world: false
  authorize { current_user.present? }

  arguments do
    required(:project_id).filled(:integer).description("The project ID")
    required(:invitation_id).filled(:integer).description("The invitation ID to cancel")
  end

  def call(project_id:, invitation_id:)
    error = require_project(project_id)
    return error if error

    with_error_handling do
      unless current_project.owner?(current_user)
        return { error: "forbidden", message: "Only project owners can cancel invitations" }.to_json
      end

      invitation = current_project.project_invitations.find(invitation_id)

      unless invitation.pending?
        return { error: "already_accepted", message: "This invitation has already been accepted" }.to_json
      end

      invitation.destroy!

      { success: true, message: "Invitation to #{invitation.email} cancelled" }.to_json
    end
  end
end
