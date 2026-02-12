# frozen_string_literal: true

require "test_helper"

class ProjectMembershipsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @owner = users(:alice)
    @member = users(:bob)
    @project = projects(:alice_project)
    @member_membership = project_memberships(:bob_member_of_alice_project)
  end

  # Authentication

  test "requires authentication" do
    get project_memberships_path(@project)
    assert_redirected_to new_session_path
  end

  # Index

  test "owner can view members" do
    sign_in(@owner)
    get project_memberships_path(@project)
    assert_response :success
    assert_select ".project-members__email", @owner.email
    assert_select ".project-members__email", @member.email
  end

  test "member can view members" do
    sign_in(@member)
    get project_memberships_path(@project)
    assert_response :success
    assert_select ".project-members__email", @owner.email
  end

  test "member does not see invite form" do
    sign_in(@member)
    get project_memberships_path(@project)
    assert_select ".project-members__invite", count: 0
  end

  test "owner sees invite form" do
    sign_in(@owner)
    get project_memberships_path(@project)
    assert_select ".project-members__invite"
  end

  test "non-member cannot view members" do
    other_user = users(:unconfirmed)
    other_user.update!(confirmed_at: Time.current)
    sign_in(other_user)
    get project_memberships_path(@project)
    assert_response :not_found
  end

  # Destroy

  test "owner can remove member" do
    sign_in(@owner)
    assert_difference "ProjectMembership.count", -1 do
      delete project_membership_path(@project, @member_membership)
    end
    assert_redirected_to project_memberships_path(@project)
  end

  test "owner cannot remove self" do
    owner_membership = project_memberships(:alice_owns_alice_project)
    sign_in(@owner)
    assert_no_difference "ProjectMembership.count" do
      delete project_membership_path(@project, owner_membership)
    end
    assert_redirected_to project_memberships_path(@project)
    follow_redirect!
    assert_select ".flash--alert"
  end

  test "member cannot remove others" do
    sign_in(@member)
    assert_no_difference "ProjectMembership.count" do
      delete project_membership_path(@project, project_memberships(:alice_owns_alice_project))
    end
    assert_redirected_to projects_path
  end
end
