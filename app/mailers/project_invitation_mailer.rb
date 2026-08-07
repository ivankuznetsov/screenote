# frozen_string_literal: true

class ProjectInvitationMailer < ApplicationMailer
  def invite(invitation_id, authentication_token_id)
    @invitation = ProjectInvitation.includes(:inviter, :project).find(invitation_id)
    token = @invitation.authentication_tokens.find(authentication_token_id)
    @inviter = @invitation.inviter
    @project = @invitation.project
    @presentation = AuthenticationLinks::Issuer.new(
      origin: AuthenticationLinks::Runtime.origin,
      keyring: AuthenticationLinks::Runtime.keyring
    ).re_present(token: token)
    @accept_url = @presentation.url

    mail to: @invitation.email,
         subject: "#{@inviter.email} invited you to \"#{@project.name}\" on Screenote"
  end
end
