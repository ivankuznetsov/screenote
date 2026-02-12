# frozen_string_literal: true

require "test_helper"

class ProjectInvitationTest < ActiveSupport::TestCase
  setup do
    @project = projects(:alice_project)
    @inviter = users(:alice)
  end

  test "valid invitation" do
    invitation = @project.project_invitations.build(
      inviter: @inviter,
      email: "new@example.com"
    )
    assert invitation.valid?
  end

  test "requires email" do
    invitation = @project.project_invitations.build(inviter: @inviter, email: "")
    assert_not invitation.valid?
    assert invitation.errors[:email].any?
  end

  test "requires valid email format" do
    invitation = @project.project_invitations.build(inviter: @inviter, email: "notanemail")
    assert_not invitation.valid?
  end

  test "normalizes email to lowercase" do
    invitation = @project.project_invitations.create!(inviter: @inviter, email: " SomeUser@Example.COM ")
    assert_equal "someuser@example.com", invitation.email
  end

  test "rejects duplicate email for same project" do
    @project.project_invitations.create!(inviter: @inviter, email: "dup@example.com")
    duplicate = @project.project_invitations.build(inviter: @inviter, email: "dup@example.com")
    assert_not duplicate.valid?
    assert duplicate.errors[:email].any?
  end

  test "allows same email for different projects" do
    @project.project_invitations.create!(inviter: @inviter, email: "shared@example.com")
    other_project = projects(:bob_project)
    invitation = other_project.project_invitations.build(inviter: users(:bob), email: "shared@example.com")
    assert invitation.valid?
  end

  test "rejects invitation for existing member" do
    invitation = @project.project_invitations.build(
      inviter: @inviter,
      email: users(:bob).email
    )
    assert_not invitation.valid?
    assert_includes invitation.errors[:email], "is already a member of this project"
  end

  test "generates accept token" do
    invitation = project_invitations(:pending_invitation)
    token = invitation.generate_token_for(:accept)
    assert_not_nil token

    found = ProjectInvitation.find_by_token_for(:accept, token)
    assert_equal invitation, found
  end

  test "accept token invalidates after status change" do
    invitation = project_invitations(:pending_invitation)
    token = invitation.generate_token_for(:accept)

    invitation.update!(status: :accepted)

    found = ProjectInvitation.find_by_token_for(:accept, token)
    assert_nil found
  end

  test "accept! creates membership and updates status" do
    invitation = project_invitations(:pending_invitation)
    new_user = User.create!(
      email: invitation.email,
      password: "password123",
      confirmed_at: Time.current
    )

    assert_difference "ProjectMembership.count", 1 do
      invitation.accept!(new_user)
    end

    assert invitation.accepted?
    assert @project.member?(new_user)
    assert_equal :member, @project.role_for(new_user)
  end
end
