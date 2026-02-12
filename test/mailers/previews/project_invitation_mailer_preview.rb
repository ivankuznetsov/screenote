# frozen_string_literal: true

class ProjectInvitationMailerPreview < ActionMailer::Preview
  def invite
    invitation = ProjectInvitation.first || ProjectInvitation.new(
      project: Project.first,
      inviter: User.first,
      email: "invitee@example.com"
    )
    ProjectInvitationMailer.invite(invitation)
  end
end
