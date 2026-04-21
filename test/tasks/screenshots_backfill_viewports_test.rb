# frozen_string_literal: true

require "test_helper"
require "rake"

class ScreenshotsBackfillViewportsTest < ActiveSupport::TestCase
  setup do
    # Remove the desktop fixtures so the task has real work to do.
    ScreenshotImage.delete_all

    Rails.application.load_tasks unless Rake::Task.task_defined?("screenshots:backfill_viewports")
    @task = Rake::Task["screenshots:backfill_viewports"]
    @task.reenable
  end

  teardown do
    ENV.delete("APPLY")
  end

  test "dry-run creates no ScreenshotImage rows and does not detach blobs" do
    attach_test_image_to(screenshots(:alice_screenshot))
    initial = ScreenshotImage.count

    capture_io { @task.invoke }

    assert_equal initial, ScreenshotImage.count, "Dry-run must not write rows"
    assert screenshots(:alice_screenshot).reload.image.attached?,
      "Dry-run must not detach the Screenshot's image"
  end

  test "APPLY=1 creates one desktop ScreenshotImage per Screenshot with an image and moves blob" do
    attach_test_image_to(screenshots(:alice_screenshot))
    original_blob_id = screenshots(:alice_screenshot).image.blob.id

    ENV["APPLY"] = "1"
    capture_io { @task.invoke }

    screenshot = screenshots(:alice_screenshot).reload
    assert_not screenshot.image.attached?, "Blob should have been detached from Screenshot"
    si = screenshot.screenshot_images.find_by!(viewport: :desktop)
    assert_equal original_blob_id, si.image.blob.id,
      "Same blob should now be attached to the ScreenshotImage (no S3 re-upload)"
    assert_equal screenshot.width, si.width
    assert_equal screenshot.height, si.height
    assert_equal screenshot.status, si.status
  end

  test "APPLY=1 on a screenshot without an image creates an empty desktop row" do
    screenshot = screenshots(:alice_screenshot_pending)
    assert_not screenshot.image.attached?

    ENV["APPLY"] = "1"
    capture_io { @task.invoke }

    si = screenshot.reload.screenshot_images.find_by!(viewport: :desktop)
    assert_not si.image.attached?
    assert_equal screenshot.status, si.status
  end

  test "re-running APPLY=1 is idempotent" do
    attach_test_image_to(screenshots(:alice_screenshot))

    ENV["APPLY"] = "1"
    capture_io { @task.invoke }
    count_after_first = ScreenshotImage.count

    @task.reenable
    capture_io { @task.invoke }

    assert_equal count_after_first, ScreenshotImage.count,
      "Second run should skip Screenshots that already have a desktop variant"
  end

  private

  def attach_test_image_to(screenshot)
    screenshot.image.attach(
      io: StringIO.new(File.binread(Rails.root.join("test/fixtures/files/test_image.png"))),
      filename: "test.png",
      content_type: "image/png"
    )
  end
end
