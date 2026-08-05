# frozen_string_literal: true

class InviteCollaboratorTool < ApplicationTool
  tool_name "invite_collaborator"
  description "Invite a collaborator to a project by email. Sends an invitation email. Requires owner role."
  mcp_action scope: :mcp_write, read_only: false, destructive: false, idempotent: false, open_world: true
  authorize { current_user.present? }

  arguments do
    required(:project_id).filled(:integer).description("The project ID")
    required(:email).filled(:string).description("Email address of the person to invite")
  end

  def call(project_id:, email:)
    error = require_project(project_id)
    return error if error

    with_error_handling do
      unless current_principal.can_invite_to?(current_project)
        return { error: "forbidden", message: "Only project owners can invite collaborators" }.to_json
      end

      unless current_user.can_invite_member?(current_project)
        return { error: "member_limit_exceeded", message: "Project has reached its member limit. Upgrade to Pro for unlimited members." }.to_json
      end

      invitation = current_project.project_invitations.build(email: email, inviter: current_user)

      unless invitation.save
        return { error: "validation_failed", message: invitation.errors.full_messages.to_sentence }.to_json
      end

      ProjectInvitationMailer.invite(invitation).deliver_later if Screenote::Deployment.current.mail?

      {
        invitation: {
          id: invitation.id,
          email: invitation.email,
          status: invitation.status,
          created_at: invitation.created_at.iso8601
        }
      }.to_json
    end
  end
end
