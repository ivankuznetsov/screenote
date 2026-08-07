# frozen_string_literal: true

class ProjectInvitationMailerPreview < ActionMailer::Preview
  def invite
    invitation = ProjectInvitation.pending.first
    token = invitation&.authentication_tokens&.active&.order(:generation)&.last
    raise "Create a pending invitation link before previewing this mail" unless invitation && token

    ProjectInvitationMailer.invite(invitation.id, token.id)
  end
end
