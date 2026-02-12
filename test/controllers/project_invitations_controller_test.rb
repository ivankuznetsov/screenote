# frozen_string_literal: true

require "test_helper"

class ProjectInvitationsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @owner = users(:alice)
    @member = users(:bob)
    @project = projects(:alice_project)
    @invitation = project_invitations(:pending_invitation)
  end

  # Authorization

  test "requires authentication" do
    post project_invitations_path(@project), params: { project_invitation: { email: "x@example.com" } }
    assert_redirected_to new_session_path
  end

  test "requires owner role to create" do
    sign_in(@member)
    post project_invitations_path(@project), params: { project_invitation: { email: "x@example.com" } }
    assert_redirected_to projects_path
  end

  test "requires owner role to destroy" do
    sign_in(@member)
    delete project_invitation_path(@project, @invitation)
    assert_redirected_to projects_path
  end

  # Create

  test "owner can send invitation" do
    sign_in(@owner)
    assert_difference "ProjectInvitation.count", 1 do
      post project_invitations_path(@project), params: { project_invitation: { email: "invitee@example.com" } }
    end
    assert_redirected_to project_memberships_path(@project)
  end

  test "sends invitation email" do
    sign_in(@owner)
    assert_enqueued_emails 1 do
      post project_invitations_path(@project), params: { project_invitation: { email: "invitee@example.com" } }
    end
  end

  test "rejects invalid email" do
    sign_in(@owner)
    assert_no_difference "ProjectInvitation.count" do
      post project_invitations_path(@project), params: { project_invitation: { email: "" } }
    end
    assert_redirected_to project_memberships_path(@project)
    follow_redirect!
    assert_select ".flash--alert"
  end

  test "rejects duplicate invitation" do
    sign_in(@owner)
    assert_no_difference "ProjectInvitation.count" do
      post project_invitations_path(@project), params: { project_invitation: { email: @invitation.email } }
    end
    assert_redirected_to project_memberships_path(@project)
  end

  # Destroy

  test "owner can cancel pending invitation" do
    sign_in(@owner)
    assert_difference "ProjectInvitation.count", -1 do
      delete project_invitation_path(@project, @invitation)
    end
    assert_redirected_to project_memberships_path(@project)
  end
end
