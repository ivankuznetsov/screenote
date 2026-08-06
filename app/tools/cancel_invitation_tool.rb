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
      result = ProjectInvitations::Cancel.call(
        principal: current_principal,
        project: current_project,
        invitation_id: invitation_id
      )

      case result.status
      when :cancelled
        { success: true, status: "cancelled", invitation_id: result.invitation.id }.to_json
      when :already_cancelled
        { success: true, status: "already_cancelled", invitation_id: result.invitation.id }.to_json
      when :already_accepted
        { error: "already_accepted", message: "This invitation has already been accepted" }.to_json
      when :forbidden
        { error: "forbidden", message: "Only active project owners can cancel invitations" }.to_json
      when :not_found
        { error: "not_found", message: "Project invitation not found" }.to_json
      when :retryable_busy
        { error: "retryable_busy", message: "Invitation cancellation is busy; retry the request" }.to_json
      end
    end
  end
end
