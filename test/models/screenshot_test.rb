# frozen_string_literal: true

require "test_helper"

class ScreenshotTest < ActiveSupport::TestCase
  test "valid screenshot with title and project" do
    screenshot = Screenshot.new(title: "Test", project: projects(:alice_project))
    assert screenshot.valid?, "Screenshot should be valid with title and project"
  end

  test "requires title" do
    screenshot = Screenshot.new(project: projects(:alice_project))
    assert_not screenshot.valid?, "Screenshot should be invalid without title"
    assert screenshot.errors[:title].any?, "Should have title error"
  end

  test "requires project" do
    screenshot = Screenshot.new(title: "Test")
    assert_not screenshot.valid?, "Screenshot should be invalid without project"
  end

  test "width must be positive integer" do
    screenshot = Screenshot.new(title: "Test", project: projects(:alice_project), width: -1)
    assert_not screenshot.valid?, "Screenshot should be invalid with negative width"

    screenshot.width = 0
    assert_not screenshot.valid?, "Screenshot should be invalid with zero width"

    screenshot.width = 1920
    assert screenshot.valid?, "Screenshot should be valid with positive width"
  end

  test "height must be positive integer" do
    screenshot = Screenshot.new(title: "Test", project: projects(:alice_project), height: -1)
    assert_not screenshot.valid?, "Screenshot should be invalid with negative height"

    screenshot.height = 1080
    assert screenshot.valid?, "Screenshot should be valid with positive height"
  end

  test "width and height are optional" do
    screenshot = Screenshot.new(title: "Test", project: projects(:alice_project))
    assert screenshot.valid?, "Screenshot should be valid without dimensions"
  end

  test "belongs to project" do
    screenshot = screenshots(:alice_screenshot)
    assert_equal projects(:alice_project), screenshot.project
  end

  test "has many annotations" do
    screenshot = screenshots(:alice_screenshot)
    assert screenshot.annotations.count >= 2, "Should have annotations"
  end

  test "default status is pending" do
    screenshot = Screenshot.new
    assert_equal "pending", screenshot.status
  end

  test "status enum values" do
    assert_equal 0, Screenshot.statuses[:pending]
    assert_equal 1, Screenshot.statuses[:ready]
    assert_equal 2, Screenshot.statuses[:failed]
  end

  test "destroying screenshot destroys annotations" do
    screenshot = screenshots(:alice_screenshot)
    annotation_count = screenshot.annotations.count
    assert annotation_count > 0, "Should have annotations to destroy"

    assert_difference "Annotation.count", -annotation_count do
      screenshot.destroy
    end
  end
end
