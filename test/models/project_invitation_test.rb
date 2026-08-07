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

  test "requires a project without running membership lookup" do
    invitation = ProjectInvitation.new(inviter: @inviter, email: "orphan@example.com")

    assert_not invitation.valid?
    assert_includes invitation.errors[:project], "must exist"
  end

  test "requires valid email format" do
    invitation = @project.project_invitations.build(inviter: @inviter, email: "notanemail")
    assert_not invitation.valid?
  end

  test "normalizes email to lowercase" do
    invitation = @project.project_invitations.create!(inviter: @inviter, email: " SomeUser@Example.COM ")
    assert_equal "someuser@example.com", invitation.email
  end

  test "rejects duplicate pending email for same project" do
    @project.project_invitations.create!(inviter: @inviter, email: "dup@example.com")
    duplicate = @project.project_invitations.build(inviter: @inviter, email: "dup@example.com")
    assert_not duplicate.valid?
    assert duplicate.errors[:email].any?
  end

  test "allows re-invitation after member was removed" do
    invitation = @project.project_invitations.create!(inviter: @inviter, email: "reinvite@example.com")
    user = User.create!(email: "reinvite@example.com", password: "password123", confirmed_at: Time.current)
    invitation.update!(status: :accepted)
    @project.project_memberships.create!(user: user, role: :member)

    # Remove the member
    @project.project_memberships.find_by(user: user).destroy

    new_invitation = @project.project_invitations.build(inviter: @inviter, email: "reinvite@example.com")
    assert new_invitation.valid?, "Should allow re-invitation after member was removed"
  end

  test "allows same email for different projects" do
    @project.project_invitations.create!(inviter: @inviter, email: "shared@example.com")
    other_project = projects(:bob_project)
    invitation = other_project.project_invitations.build(inviter: users(:bob), email: "shared@example.com")
    assert invitation.valid?
  end

  test "cancelled invitations remain as durable terminal rows and allow reissue" do
    invitation = @project.project_invitations.create!(inviter: @inviter, email: "cancelled@example.com")
    invitation.update!(status: :cancelled)

    assert invitation.cancelled?
    replacement = @project.project_invitations.build(inviter: @inviter, email: invitation.email)
    assert replacement.valid?
  end

  test "rejects unknown terminal states" do
    invitation = @project.project_invitations.build(
      inviter: @inviter,
      email: "unknown-state@example.com",
      status: :unknown
    )

    assert_not invitation.valid?
    assert_includes invitation.errors[:status], "is not included in the list"
  end

  test "destroying an invitation also destroys its authentication grants" do
    invitation = @project.project_invitations.create!(
      inviter: @inviter,
      email: "destroyed@example.com"
    )
    keyring = AuthenticationLinks::Keyring.new(
      secret_key_base: "project-invitation-model-test-secret-0123456789"
    )
    issuer = AuthenticationLinks::Issuer.new(
      origin: "https://screenote.example.test",
      keyring: keyring,
      clock: -> { Time.utc(2026, 8, 5, 12) }
    )
    token = nil
    ProjectInvitation.transaction do
      locked = ProjectInvitation.lock.find(invitation.id)
      token = issuer.call(
        purpose: :invitation,
        subject: locked,
        expires_at: Time.utc(2026, 8, 12, 12)
      ).token
    end

    invitation.destroy!

    assert_not AuthenticationToken.exists?(token.id)
  end

  test "rejects invitation for existing member" do
    invitation = @project.project_invitations.build(
      inviter: @inviter,
      email: users(:bob).email
    )
    assert_not invitation.valid?
    assert_includes invitation.errors[:email], "is already a member of this project"
  end

  test "legacy signed acceptance token API is unavailable" do
    invitation = project_invitations(:pending_invitation)

    assert_not ProjectInvitation.token_definitions.key?(:accept)
    assert_raises(KeyError) { invitation.generate_token_for(:accept) }
    assert_raises(KeyError) { ProjectInvitation.find_by_token_for(:accept, "legacy-token") }
    assert_not invitation.respond_to?(:accept!)
  end
end
