# frozen_string_literal: true

require "test_helper"

class ScreenshotImageRollbackServiceTest < ActiveSupport::TestCase
  setup do
    ScreenshotImage.delete_all
    # Simulate the post-backfill state: Screenshot has no image, the ScreenshotImage does.
    @screenshot = screenshots(:alice_screenshot)
    @screenshot.image.purge if @screenshot.image.attached?
    @screenshot_image = ScreenshotImage.create!(
      screenshot: @screenshot, viewport: :desktop, status: :ready,
      width: 1920, height: 1080
    )
    @screenshot_image.image.attach(
      io: StringIO.new(File.binread(Rails.root.join("test/fixtures/files/test_image.png"))),
      filename: "test.png", content_type: "image/png"
    )
    @original_blob_id = @screenshot_image.image.blob.id
  end

  test "dry run reports work but does not touch data" do
    result = capture_io { ScreenshotImageRollbackService.new.call }
    _, _ = result

    assert @screenshot_image.reload.image.attached?, "SI image should still be attached after dry run"
    assert_not @screenshot.reload.image.attached?, "Screenshot image should still be detached after dry run"
  end

  test "apply restores the blob to Screenshot and destroys the ScreenshotImage" do
    result = nil
    capture_io { result = ScreenshotImageRollbackService.new(apply: true).call }

    assert_equal 1, result.rolled_back
    assert @screenshot.reload.image.attached?, "Screenshot should own the blob again"
    assert_equal @original_blob_id, @screenshot.image.blob.id, "Same blob, no re-upload"
    assert_not ScreenshotImage.exists?(@screenshot_image.id), "ScreenshotImage should be destroyed"
  end

  test "is idempotent when Screenshot already has image" do
    capture_io { ScreenshotImageRollbackService.new(apply: true).call }
    count_after_first = ScreenshotImage.count

    result = nil
    capture_io { result = ScreenshotImageRollbackService.new(apply: true).call }

    assert_equal count_after_first, ScreenshotImage.count
    assert_equal 0, result.rolled_back
  end
end
