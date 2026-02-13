# frozen_string_literal: true

require "test_helper"

class ProjectInvitationMailerTest < ActionMailer::TestCase
  test "invite sends email with correct details" do
    invitation = project_invitations(:pending_invitation)
    email = ProjectInvitationMailer.invite(invitation)

    assert_emails 1 do
      email.deliver_now
    end

    assert_equal [ invitation.email ], email.to
    assert_includes email.subject, invitation.inviter.email
    assert_includes email.subject, invitation.project.name
    assert_includes email.body.encoded, "Accept invitation"
    assert_includes email.body.encoded, "invitations/"
  end
end
