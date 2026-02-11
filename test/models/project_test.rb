# frozen_string_literal: true

require "test_helper"

class ProjectTest < ActiveSupport::TestCase
  test "valid project with name and user" do
    project = Project.new(name: "Test", user: users(:alice))
    assert project.valid?, "Project should be valid with name and user"
  end

  test "requires name" do
    project = Project.new(user: users(:alice))
    assert_not project.valid?, "Project should be invalid without name"
    assert project.errors[:name].any?, "Should have name error"
  end

  test "requires user" do
    project = Project.new(name: "Test")
    assert_not project.valid?, "Project should be invalid without user"
  end

  test "name max length 255" do
    project = Project.new(name: "a" * 256, user: users(:alice))
    assert_not project.valid?, "Project should be invalid with name > 255 chars"

    project.name = "a" * 255
    assert project.valid?, "Project should be valid with name = 255 chars"
  end

  test "description is optional" do
    project = Project.new(name: "Test", user: users(:alice))
    assert project.valid?, "Project should be valid without description"
  end

  test "belongs to user" do
    project = projects(:alice_project)
    assert_equal users(:alice), project.user
  end
end
