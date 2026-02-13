# frozen_string_literal: true

class ProjectInvitationMailer < ApplicationMailer
  def invite(invitation)
    @invitation = invitation
    @inviter = invitation.inviter
    @project = invitation.project
    @accept_url = accept_invitation_url(invitation.generate_token_for(:accept))

    mail to: invitation.email,
         subject: "#{@inviter.email} invited you to \"#{@project.name}\" on Screenote"
  end
end
