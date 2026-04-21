# frozen_string_literal: true

require "test_helper"

class ScreenshotDimensionJobTest < ActiveSupport::TestCase
  setup do
    @page = pages(:alice_page)
  end

  test "sets dimensions and status to ready for ScreenshotImage with valid image" do
    screenshot = @page.screenshots.create!(title: "Dimension Test")
    si = screenshot.screenshot_images.create!(viewport: :desktop)
    si.image.attach(
      io: File.open(Rails.root.join("test/fixtures/files/test_image.png")),
      filename: "test.png", content_type: "image/png"
    )

    ScreenshotDimensionJob.perform_now(si)

    si.reload
    assert si.status_ready?
    assert si.width.present?
    assert si.height.present?
  end

  test "skips already ready ScreenshotImage" do
    si = screenshot_images(:alice_screenshot_desktop)
    original_width = si.width

    ScreenshotDimensionJob.perform_now(si)

    assert_equal original_width, si.reload.width
  end

  test "returns early when ScreenshotImage has no image attached" do
    screenshot = @page.screenshots.create!(title: "No image")
    si = screenshot.screenshot_images.create!(viewport: :desktop)

    assert_nothing_raised { ScreenshotDimensionJob.perform_now(si) }
    assert si.reload.status_pending?
  end

  test "forwards legacy Screenshot argument to its primary ScreenshotImage" do
    si = screenshot_images(:alice_screenshot_desktop)
    si.image.attach(
      io: File.open(Rails.root.join("test/fixtures/files/test_image.png")),
      filename: "test.png", content_type: "image/png"
    )
    si.update!(status: :pending, width: nil, height: nil)

    ScreenshotDimensionJob.perform_now(si.screenshot)

    assert si.reload.status_ready?
  end

  test "no-op when Screenshot has no primary_image" do
    screenshot = @page.screenshots.create!(title: "Orphan")

    assert_nothing_raised { ScreenshotDimensionJob.perform_now(screenshot) }
  end
end
