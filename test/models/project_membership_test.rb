# frozen_string_literal: true

# screenote-edition: self_hosted

require "test_helper"

class ProjectMembershipTest < ActiveSupport::TestCase
  test "valid membership" do
    user = User.create!(email: "member@example.com", password: "password123", confirmed_at: Time.current)
    membership = ProjectMembership.new(project: projects(:bob_project), user: user, role: :member)
    assert membership.valid?
  end

  test "rejects duplicate user per project" do
    membership = ProjectMembership.new(
      project: projects(:alice_project),
      user: users(:alice),
      role: :member
    )
    assert_not membership.valid?
    assert membership.errors[:user_id].any?
  end

  test "requires role" do
    membership = ProjectMembership.new(
      project: projects(:alice_project),
      user: User.create!(email: "norole@example.com", password: "password123", confirmed_at: Time.current),
      role: nil
    )
    assert_not membership.valid?
  end

  test "owner role" do
    membership = project_memberships(:alice_owns_alice_project)
    assert membership.owner?
    assert_not membership.member?
  end

  test "member role" do
    membership = project_memberships(:bob_member_of_alice_project)
    assert membership.member?
    assert_not membership.owner?
  end

  test "cannot destroy sole owner membership" do
    owner_membership = project_memberships(:alice_owns_alice_project)
    assert_not owner_membership.destroy, "Should not destroy sole owner"
    assert_includes owner_membership.errors[:base], "Cannot remove the only owner of a project"
  end

  test "can destroy member membership" do
    member_membership = project_memberships(:bob_member_of_alice_project)
    assert member_membership.destroy, "Should allow destroying member membership"
  end
end
