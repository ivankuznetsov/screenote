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
end
