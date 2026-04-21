# frozen_string_literal: true

require "test_helper"

# Covers ScreenshotImage.backfill_from_screenshots! and
# ScreenshotImage.rollback_to_screenshots!.
class ScreenshotImageBackfillTest < ActiveSupport::TestCase
  setup do
    ScreenshotImage.delete_all
  end

  test "backfill dry-run creates no rows and leaves Screenshot images attached" do
    attach_test_image_to(screenshots(:alice_screenshot))

    result = ScreenshotImage.backfill_from_screenshots!(logger: StringIO.new)

    assert_equal 0, ScreenshotImage.count
    assert screenshots(:alice_screenshot).reload.image.attached?
    assert_equal 0, result.backfilled
  end

  test "backfill apply moves the blob to a new desktop ScreenshotImage" do
    attach_test_image_to(screenshots(:alice_screenshot))
    original_blob_id = screenshots(:alice_screenshot).image.blob.id

    result = ScreenshotImage.backfill_from_screenshots!(apply: true, logger: StringIO.new)

    assert_equal 1, result.backfilled
    screenshot = screenshots(:alice_screenshot).reload
    assert_not screenshot.image.attached?
    si = screenshot.screenshot_images.find_by!(viewport: :desktop)
    assert_equal original_blob_id, si.image.blob.id
    assert_equal screenshot.width, si.width
    assert_equal screenshot.height, si.height
    assert_equal screenshot.status, si.status
  end

  test "backfill leaves Screenshots without an image untouched" do
    assert_not screenshots(:alice_screenshot_pending).image.attached?

    result = ScreenshotImage.backfill_from_screenshots!(apply: true, logger: StringIO.new)

    assert_equal 0, screenshots(:alice_screenshot_pending).reload.screenshot_images.count
    assert result.no_image >= 1
  end

  test "backfill re-run is idempotent" do
    attach_test_image_to(screenshots(:alice_screenshot))

    ScreenshotImage.backfill_from_screenshots!(apply: true, logger: StringIO.new)
    count_after_first = ScreenshotImage.count

    result = ScreenshotImage.backfill_from_screenshots!(apply: true, logger: StringIO.new)
    assert_equal count_after_first, ScreenshotImage.count
    assert_equal 0, result.backfilled
    assert result.already_backfilled >= 1
  end

  test "rollback apply restores the blob and destroys the ScreenshotImage" do
    screenshot = screenshots(:alice_screenshot)
    screenshot.image.purge if screenshot.image.attached?
    si = ScreenshotImage.create!(screenshot: screenshot, viewport: :desktop, status: :ready, width: 100, height: 100)
    attach_test_image_to(si)
    original_blob_id = si.image.blob.id

    result = ScreenshotImage.rollback_to_screenshots!(apply: true, logger: StringIO.new)

    assert_equal 1, result.rolled_back
    assert screenshot.reload.image.attached?
    assert_equal original_blob_id, screenshot.image.blob.id
    assert_not ScreenshotImage.exists?(si.id)
  end

  test "rollback is idempotent when Screenshot already has the image" do
    screenshot = screenshots(:alice_screenshot)
    screenshot.image.purge if screenshot.image.attached?
    si = ScreenshotImage.create!(screenshot: screenshot, viewport: :desktop)
    attach_test_image_to(si)

    ScreenshotImage.rollback_to_screenshots!(apply: true, logger: StringIO.new)
    count_after_first = ScreenshotImage.count

    result = ScreenshotImage.rollback_to_screenshots!(apply: true, logger: StringIO.new)
    assert_equal count_after_first, ScreenshotImage.count
    assert_equal 0, result.rolled_back
  end

  private

  def attach_test_image_to(record)
    record.image.attach(
      io: StringIO.new(File.binread(Rails.root.join("test/fixtures/files/test_image.png"))),
      filename: "test.png",
      content_type: "image/png"
    )
  end
end
