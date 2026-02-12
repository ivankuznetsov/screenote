# frozen_string_literal: true

require "test_helper"

class InvitationAcceptancesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @invitation = project_invitations(:pending_invitation)
    @token = @invitation.generate_token_for(:accept)
    @project = @invitation.project
  end

  # Show

  test "show renders confirmation page with valid token" do
    get accept_invitation_path(@token)
    assert_response :success
    assert_select ".invitation-acceptance"
    assert_select ".invitation-acceptance__button"
  end

  test "show redirects with invalid token" do
    get accept_invitation_path("invalid-token")
    assert_redirected_to root_path
  end

  # Create — existing user

  test "accepts invitation for existing user" do
    existing_user = User.create!(
      email: @invitation.email,
      password: "password123",
      confirmed_at: Time.current
    )

    assert_difference "ProjectMembership.count", 1 do
      post accept_invitation_path(@token)
    end

    assert_redirected_to project_path(@project)
    assert @project.member?(existing_user)
    @invitation.reload
    assert @invitation.accepted?
  end

  # Create — new user

  test "creates account for new user and accepts invitation" do
    assert_difference [ "User.count", "ProjectMembership.count" ], 1 do
      post accept_invitation_path(@token)
    end

    new_user = User.find_by(email: @invitation.email)
    assert_not_nil new_user
    assert_not_nil new_user.confirmed_at, "New user should be auto-confirmed"
    assert @project.member?(new_user)
    assert_redirected_to project_path(@project)
  end

  # Create — invalid/expired token

  test "rejects invalid token" do
    post accept_invitation_path("bogus-token")
    assert_redirected_to root_path
  end

  test "rejects token from before status change" do
    # Accept once using the original token
    post accept_invitation_path(@token)
    assert_redirected_to project_path(@project)

    # Original token should be invalidated because status changed
    found = ProjectInvitation.find_by_token_for(:accept, @token)
    assert_nil found, "Original token should be invalidated after acceptance"
  end

  # Create — logged in as different user

  test "logs out different user and accepts with correct user" do
    different_user = users(:alice)
    sign_in(different_user)

    existing_user = User.create!(
      email: @invitation.email,
      password: "password123",
      confirmed_at: Time.current
    )

    post accept_invitation_path(@token)
    assert_redirected_to project_path(@project)
    assert @project.member?(existing_user)
  end

  # Create — already logged in as correct user

  test "accepts when already logged in with matching email" do
    existing_user = User.create!(
      email: @invitation.email,
      password: "password123",
      confirmed_at: Time.current
    )
    sign_in(existing_user)

    assert_difference "ProjectMembership.count", 1 do
      post accept_invitation_path(@token)
    end

    assert_redirected_to project_path(@project)
  end
end
