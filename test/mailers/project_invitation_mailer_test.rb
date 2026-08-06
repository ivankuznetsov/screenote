# frozen_string_literal: true

require "test_helper"

class ProjectInvitationMailerTest < ActionMailer::TestCase
  test "invite sends email with correct details" do
    invitation = project_invitations(:pending_invitation)
    token = nil
    ProjectInvitation.transaction do
      token = AuthenticationLinks::Issuer.new(
        origin: AuthenticationLinks::Runtime.origin,
        keyring: AuthenticationLinks::Runtime.keyring
      ).call(
        purpose: :invitation,
        subject: ProjectInvitation.lock.find(invitation.id),
        expires_at: 7.days.from_now
      ).token
    end
    email = ProjectInvitationMailer.invite(invitation.id, token.id)

    assert_emails 1 do
      email.deliver_now
    end

    assert_equal [ invitation.email ], email.to
    assert_includes email.subject, invitation.inviter.email
    assert_includes email.subject, invitation.project.name
    assert_includes email.body.encoded, "Accept Invitation"
    assert_includes email.body.encoded, "authentication-links/invitation"
    assert_includes email.body.encoded, "v1."
  end
end
