# frozen_string_literal: true

# screenote-edition: self_hosted

require "test_helper"

class ProjectTest < ActiveSupport::TestCase
  test "valid project with name and creator" do
    project = Project.new(name: "Test", creator: users(:alice))
    assert project.valid?, "Project should be valid with name and creator"
  end

  test "requires name" do
    project = Project.new(creator: users(:alice))
    assert_not project.valid?, "Project should be invalid without name"
    assert project.errors[:name].any?, "Should have name error"
  end

  test "requires creator" do
    project = Project.new(name: "Test")
    assert_not project.valid?, "Project should be invalid without creator"
  end

  test "name max length 255" do
    project = Project.new(name: "a" * 256, creator: users(:alice))
    assert_not project.valid?, "Project should be invalid with name > 255 chars"

    project.name = "a" * 255
    assert project.valid?, "Project should be valid with name = 255 chars"
  end

  test "description is optional" do
    project = Project.new(name: "Test", creator: users(:alice))
    assert project.valid?, "Project should be valid without description"
  end

  test "belongs to creator" do
    project = projects(:alice_project)
    assert_equal users(:alice), project.creator
  end

  test "creates owner membership on create" do
    project = Project.create!(name: "New Project", creator: users(:alice))
    assert project.project_memberships.exists?(user: users(:alice), role: :owner),
      "Should create owner membership for creator"
  end

  test "destroy removes project-scoped oauth grants and tokens" do
    user = users(:alice)
    project = user.owned_projects.create!(name: "Disposable OAuth project")
    application = create_oauth_application(name: "Disposable OAuth app")
    token = create_oauth_token(
      application: application,
      user: user,
      project: project,
      scopes: "mcp_read"
    )
    grant = Doorkeeper::AccessGrant.create!(
      application: application,
      resource_owner_id: user.id,
      principal_kind: "project",
      project_id: project.id,
      expires_in: 10.minutes.to_i,
      redirect_uri: application.redirect_uri,
      scopes: "mcp_read"
    )

    project.destroy!

    assert_not Doorkeeper::AccessToken.exists?(token.id)
    assert_not Doorkeeper::AccessGrant.exists?(grant.id)
  end

  test "member? returns true for members" do
    project = projects(:alice_project)
    assert project.member?(users(:alice)), "Creator should be a member"
  end

  test "member? returns true for member role" do
    project = projects(:alice_project)
    assert project.member?(users(:bob)), "Bob should be a member of Alice's project"
  end

  test "member? returns false for non-members" do
    project = projects(:alice_project)
    assert_not project.member?(users(:unconfirmed)), "Non-member should not be a member"
  end

  test "owner? returns true for owner" do
    project = projects(:alice_project)
    assert project.owner?(users(:alice)), "Creator should be owner"
  end

  test "owner? returns false for non-owner member" do
    project = projects(:alice_project)
    assert_not project.owner?(users(:bob)), "Member should not be owner"
  end

  test "owner? returns false for non-member" do
    project = projects(:alice_project)
    assert_not project.owner?(users(:unconfirmed)), "Non-member should not be owner"
  end

  test "role_for returns role symbol" do
    project = projects(:alice_project)
    assert_equal :owner, project.role_for(users(:alice))
  end

  test "role_for returns member for member" do
    project = projects(:alice_project)
    assert_equal :member, project.role_for(users(:bob))
  end

  test "role_for returns nil for non-member" do
    project = projects(:alice_project)
    assert_nil project.role_for(users(:unconfirmed))
  end
end
