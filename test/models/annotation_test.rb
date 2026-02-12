# frozen_string_literal: true

require "test_helper"

class AnnotationTest < ActiveSupport::TestCase
  test "valid point annotation" do
    annotation = Annotation.new(
      screenshot: screenshots(:alice_screenshot),
      user: users(:alice),
      x_percent: 50.0,
      y_percent: 30.0,
      comment: "Test comment"
    )
    assert annotation.valid?, "Point annotation should be valid"
  end

  test "valid region annotation" do
    annotation = Annotation.new(
      screenshot: screenshots(:alice_screenshot),
      user: users(:alice),
      x_percent: 10.0,
      y_percent: 20.0,
      width_percent: 30.0,
      height_percent: 25.0,
      comment: "Region comment"
    )
    assert annotation.valid?, "Region annotation should be valid"
  end

  test "requires x_percent" do
    annotation = Annotation.new(
      screenshot: screenshots(:alice_screenshot),
      user: users(:alice),
      y_percent: 30.0
    )
    assert_not annotation.valid?, "Should require x_percent"
    assert annotation.errors[:x_percent].any?
  end

  test "requires y_percent" do
    annotation = Annotation.new(
      screenshot: screenshots(:alice_screenshot),
      user: users(:alice),
      x_percent: 50.0
    )
    assert_not annotation.valid?, "Should require y_percent"
    assert annotation.errors[:y_percent].any?
  end

  test "x_percent must be between 0 and 100" do
    annotation = Annotation.new(
      screenshot: screenshots(:alice_screenshot),
      user: users(:alice),
      comment: "Test",
      x_percent: -1.0,
      y_percent: 50.0
    )
    assert_not annotation.valid?, "x_percent should not be negative"

    annotation.x_percent = 101.0
    assert_not annotation.valid?, "x_percent should not exceed 100"

    annotation.x_percent = 0.0
    assert annotation.valid?, "x_percent 0.0 should be valid"

    annotation.x_percent = 100.0
    assert annotation.valid?, "x_percent 100.0 should be valid"
  end

  test "y_percent must be between 0 and 100" do
    annotation = Annotation.new(
      screenshot: screenshots(:alice_screenshot),
      user: users(:alice),
      x_percent: 50.0,
      y_percent: -1.0
    )
    assert_not annotation.valid?, "y_percent should not be negative"

    annotation.y_percent = 101.0
    assert_not annotation.valid?, "y_percent should not exceed 100"
  end

  test "width_percent must be positive when present" do
    annotation = Annotation.new(
      screenshot: screenshots(:alice_screenshot),
      user: users(:alice),
      x_percent: 10.0,
      y_percent: 20.0,
      width_percent: 0.0,
      height_percent: 25.0
    )
    assert_not annotation.valid?, "width_percent should not be zero"

    annotation.width_percent = -5.0
    assert_not annotation.valid?, "width_percent should not be negative"
  end

  test "height_percent must be positive when present" do
    annotation = Annotation.new(
      screenshot: screenshots(:alice_screenshot),
      user: users(:alice),
      x_percent: 10.0,
      y_percent: 20.0,
      width_percent: 30.0,
      height_percent: 0.0
    )
    assert_not annotation.valid?, "height_percent should not be zero"
  end

  test "region must not extend beyond image boundary horizontally" do
    annotation = Annotation.new(
      screenshot: screenshots(:alice_screenshot),
      user: users(:alice),
      x_percent: 80.0,
      y_percent: 20.0,
      width_percent: 25.0,
      height_percent: 10.0
    )
    assert_not annotation.valid?, "Region extending past right edge should be invalid"
    assert annotation.errors[:width_percent].any?
  end

  test "region must not extend beyond image boundary vertically" do
    annotation = Annotation.new(
      screenshot: screenshots(:alice_screenshot),
      user: users(:alice),
      x_percent: 20.0,
      y_percent: 85.0,
      width_percent: 10.0,
      height_percent: 20.0
    )
    assert_not annotation.valid?, "Region extending past bottom edge should be invalid"
    assert annotation.errors[:height_percent].any?
  end

  test "point? returns true when width_percent is nil" do
    annotation = annotations(:point_annotation)
    assert annotation.point?, "Should be a point annotation"
  end

  test "point? returns false when width_percent is present" do
    annotation = annotations(:region_annotation)
    assert_not annotation.point?, "Should not be a point annotation"
  end

  test "default status is open" do
    annotation = Annotation.new
    assert_equal "open", annotation.status
  end

  test "status enum values" do
    assert_equal 0, Annotation.statuses[:open]
    assert_equal 1, Annotation.statuses[:resolved]
  end

  test "belongs to screenshot" do
    annotation = annotations(:point_annotation)
    assert_equal screenshots(:alice_screenshot), annotation.screenshot
  end

  test "belongs to user" do
    annotation = annotations(:point_annotation)
    assert_equal users(:alice), annotation.user
  end

  test "requires comment" do
    annotation = Annotation.new(
      screenshot: screenshots(:alice_screenshot),
      user: users(:alice),
      x_percent: 50.0,
      y_percent: 30.0,
      comment: ""
    )
    assert_not annotation.valid?, "Should require comment"
    assert annotation.errors[:comment].any?
  end

  test "comment cannot exceed 5000 characters" do
    annotation = Annotation.new(
      screenshot: screenshots(:alice_screenshot),
      user: users(:alice),
      x_percent: 50.0,
      y_percent: 30.0,
      comment: "a" * 5001
    )
    assert_not annotation.valid?, "Comment exceeding 5000 chars should be invalid"
    assert annotation.errors[:comment].any?
  end

  test "resolved_by_user is optional" do
    annotation = Annotation.new(
      screenshot: screenshots(:alice_screenshot),
      user: users(:alice),
      comment: "Test",
      x_percent: 50.0,
      y_percent: 30.0
    )
    assert annotation.valid?, "Should be valid without resolved_by_user"
  end
end
