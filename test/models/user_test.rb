# frozen_string_literal: true

require "test_helper"

class UserTest < ActiveSupport::TestCase
  test "valid user with email and password" do
    user = User.new(email: "new@example.com", password: "password123")
    assert user.valid?, "User should be valid with email and password"
  end

  test "requires email" do
    user = User.new(password: "password123")
    assert_not user.valid?, "User should be invalid without email"
    assert user.errors[:email].any?, "Should have email error"
  end

  test "requires unique email" do
    User.create!(email: "dupe@example.com", password: "password123")
    user = User.new(email: "dupe@example.com", password: "password123")
    assert_not user.valid?, "User should be invalid with duplicate email"
  end

  test "email is normalized to lowercase" do
    user = User.create!(email: "Test@Example.COM", password: "password123")
    assert_equal "test@example.com", user.email
  end

  test "has many sessions" do
    user = users(:alice)
    assert_respond_to user, :sessions
  end

  test "has many projects" do
    user = users(:alice)
    assert_respond_to user, :projects
  end

  test "destroying user destroys sessions" do
    user = users(:alice)
    assert_difference "Session.count", -user.sessions.count do
      user.destroy
    end
  end

  test "destroying user destroys projects" do
    user = users(:alice)
    assert_difference "Project.count", -user.projects.count do
      user.destroy
    end
  end

  test "assign_oauth_attributes stores provider and uid" do
    user = User.new(email: "oauth@example.com", password: "password123")
    user.assign_oauth_attributes({
      "provider" => "google_oauth2",
      "uid" => "12345",
      "info" => { "email" => "oauth@example.com" }
    })
    assert_equal "google_oauth2", user.oauth_provider
    assert_equal "12345", user.oauth_uid
  end

  test "find_by_oauth finds user by provider and uid" do
    user = users(:alice)
    user.update!(oauth_provider: "github", oauth_uid: "999")

    found = User.find_by_oauth("github", "999")
    assert_equal user, found
  end

  test "find_by_oauth returns nil for unknown" do
    assert_nil User.find_by_oauth("github", "nonexistent")
  end

  # Subscription delegation tests

  test "pro? returns false when user has no subscription" do
    user = users(:unconfirmed)
    assert_nil user.subscription, "Precondition: user should have no subscription"
    assert_not user.pro?, "User without subscription should not be pro"
  end

  test "pro? returns false when user has free subscription" do
    user = users(:bob)
    assert_not user.pro?, "User with free subscription should not be pro"
  end

  test "pro? returns true when user has active pro subscription" do
    user = users(:alice)
    assert user.pro?, "User with active pro subscription should be pro"
  end

  test "can_create_project? returns true for user with no projects and no subscription" do
    user = users(:unconfirmed)
    assert user.can_create_project?, "User with no projects should be able to create one"
  end

  test "can_create_project? returns false for free user at project limit" do
    user = users(:bob)
    assert_equal 1, user.owned_projects.count, "Precondition: Bob should own 1 project"
    assert_not user.can_create_project?, "Free user at project limit should not create more"
  end

  test "can_create_project? returns true for pro user regardless of project count" do
    user = users(:alice)
    assert user.can_create_project?, "Pro user should always be able to create projects"
  end

  test "can_invite_member? returns true for free user project with no non-owner members" do
    user = users(:bob)
    project = projects(:bob_project)
    assert_equal 0, project.project_memberships.where(role: :member).count, "Precondition: no non-owner members"
    assert user.can_invite_member?(project), "Free user should invite when under member limit"
  end

  test "can_invite_member? returns false for free user project at member limit" do
    project = projects(:alice_project)
    user = users(:alice)
    user.subscription.update_columns(plan: :free, status: :incomplete, stripe_subscription_id: nil) # downgrade to free
    assert_equal 1, project.project_memberships.where(role: :member).count, "Precondition: 1 non-owner member (bob)"
    assert_not user.can_invite_member?(project), "Free user at member limit should not invite more"
  end

  test "can_invite_member? returns true for pro user regardless of member count" do
    user = users(:alice)
    project = projects(:alice_project)
    assert user.can_invite_member?(project), "Pro user should always invite members"
  end
end
