# frozen_string_literal: true

require "test_helper"

class ScreenshotImageBackfillServiceTest < ActiveSupport::TestCase
  setup do
    ScreenshotImage.delete_all
  end

  test "dry run creates no rows and leaves Screenshot images attached" do
    attach_test_image_to(screenshots(:alice_screenshot))

    result = silent { ScreenshotImageBackfillService.new.call }

    assert_equal 0, ScreenshotImage.count, "Dry run must not create ScreenshotImage rows"
    assert screenshots(:alice_screenshot).reload.image.attached?, "Blob must remain on Screenshot"
    assert_equal 0, result.backfilled, "No records backfilled in dry run"
  end

  test "apply creates one desktop ScreenshotImage per Screenshot with an image and moves the blob" do
    attach_test_image_to(screenshots(:alice_screenshot))
    original_blob_id = screenshots(:alice_screenshot).image.blob.id

    result = silent { ScreenshotImageBackfillService.new(apply: true).call }

    assert_equal 1, result.backfilled
    screenshot = screenshots(:alice_screenshot).reload
    assert_not screenshot.image.attached?, "Blob should have been detached from Screenshot"
    si = screenshot.screenshot_images.find_by!(viewport: :desktop)
    assert_equal original_blob_id, si.image.blob.id,
      "Same blob should now be attached to the ScreenshotImage (no S3 re-upload)"
    assert_equal screenshot.width, si.width
    assert_equal screenshot.height, si.height
    assert_equal screenshot.status, si.status
  end

  test "leaves Screenshots without an image untouched" do
    assert_not screenshots(:alice_screenshot_pending).image.attached?

    result = silent { ScreenshotImageBackfillService.new(apply: true).call }

    assert_equal 0, screenshots(:alice_screenshot_pending).reload.screenshot_images.count
    assert result.no_image >= 1
  end

  test "re-running is idempotent" do
    attach_test_image_to(screenshots(:alice_screenshot))

    silent { ScreenshotImageBackfillService.new(apply: true).call }
    count_after_first = ScreenshotImage.count

    result = silent { ScreenshotImageBackfillService.new(apply: true).call }
    assert_equal count_after_first, ScreenshotImage.count
    assert_equal 0, result.backfilled
    assert result.already_backfilled >= 1
  end

  private

  def silent(&block)
    yielded = nil
    capture_io { yielded = block.call }
    yielded
  end

  def attach_test_image_to(screenshot)
    screenshot.image.attach(
      io: StringIO.new(File.binread(Rails.root.join("test/fixtures/files/test_image.png"))),
      filename: "test.png",
      content_type: "image/png"
    )
  end
end
