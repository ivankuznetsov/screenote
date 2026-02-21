# frozen_string_literal: true

require "test_helper"

class ScreenshotTest < ActiveSupport::TestCase
  test "valid screenshot with title and project" do
    screenshot = Screenshot.new(title: "Test", page: pages(:alice_page))
    assert screenshot.valid?, "Screenshot should be valid with title and project"
  end

  test "requires title" do
    screenshot = Screenshot.new(page: pages(:alice_page))
    assert_not screenshot.valid?, "Screenshot should be invalid without title"
    assert screenshot.errors[:title].any?, "Should have title error"
  end

  test "requires page" do
    screenshot = Screenshot.new(title: "Test")
    assert_not screenshot.valid?, "Screenshot should be invalid without page"
  end

  test "width must be positive integer" do
    screenshot = Screenshot.new(title: "Test", page: pages(:alice_page), width: -1)
    assert_not screenshot.valid?, "Screenshot should be invalid with negative width"

    screenshot.width = 0
    assert_not screenshot.valid?, "Screenshot should be invalid with zero width"

    screenshot.width = 1920
    assert screenshot.valid?, "Screenshot should be valid with positive width"
  end

  test "height must be positive integer" do
    screenshot = Screenshot.new(title: "Test", page: pages(:alice_page), height: -1)
    assert_not screenshot.valid?, "Screenshot should be invalid with negative height"

    screenshot.height = 1080
    assert screenshot.valid?, "Screenshot should be valid with positive height"
  end

  test "width and height are optional" do
    screenshot = Screenshot.new(title: "Test", page: pages(:alice_page))
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

  test "generates upload token before image is attached" do
    screenshot = Screenshot.create!(title: "Token test", page: pages(:alice_page))
    token = screenshot.generate_token_for(:upload)

    assert token.present?, "Should generate a token"
    found = Screenshot.find_by_token_for(:upload, token)
    assert_equal screenshot, found, "Token should resolve to the screenshot"
  end

  test "upload token invalidates after image is attached" do
    screenshot = Screenshot.create!(title: "Token invalidation", page: pages(:alice_page))
    token = screenshot.generate_token_for(:upload)

    screenshot.image.attach(
      io: StringIO.new(File.binread(Rails.root.join("test/fixtures/files/test_image.png"))),
      filename: "test.png",
      content_type: "image/png"
    )

    found = Screenshot.find_by_token_for(:upload, token)
    assert_nil found, "Token should be invalid after image is attached"
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
