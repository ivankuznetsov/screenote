# frozen_string_literal: true

require "test_helper"

class ScreenshotDimensionJobTest < ActiveSupport::TestCase
  setup do
    @page = pages(:alice_page)
  end

  test "sets dimensions and status to ready for valid image" do
    screenshot = @page.screenshots.create!(title: "Dimension Test")
    screenshot.image.attach(
      io: File.open(Rails.root.join("test/fixtures/files/test_image.png")),
      filename: "test.png",
      content_type: "image/png"
    )

    ScreenshotDimensionJob.perform_now(screenshot)

    screenshot.reload
    assert_equal "ready", screenshot.status
    assert screenshot.width.present?, "Width should be extracted"
    assert screenshot.height.present?, "Height should be extracted"
  end

  test "skips already ready screenshot" do
    screenshot = screenshots(:alice_screenshot)
    original_width = screenshot.width

    ScreenshotDimensionJob.perform_now(screenshot)

    assert_equal original_width, screenshot.reload.width, "Should not modify already ready screenshot"
  end

  test "returns early when no image attached" do
    screenshot = screenshots(:alice_screenshot_pending)

    assert_nothing_raised do
      ScreenshotDimensionJob.perform_now(screenshot)
    end

    assert_equal "pending", screenshot.reload.status, "Should remain pending when no image attached"
  end
end
