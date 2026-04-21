# frozen_string_literal: true

require "test_helper"
require "rake"

class ScreenshotsBackfillViewportsTest < ActiveSupport::TestCase
  setup do
    # Remove the desktop fixtures so the task has real work to do.
    ScreenshotImage.delete_all

    # PR-1 doesn't define Screenshot#primary_image yet (that's PR-2). The task
    # enforces PR-2 is deployed first, so tests bypass the check with BACKFILL_FORCE.
    ENV["BACKFILL_FORCE"] = "1"

    Rails.application.load_tasks unless Rake::Task.task_defined?("screenshots:backfill_viewports")
    @task = Rake::Task["screenshots:backfill_viewports"]
    @task.reenable
  end

  teardown do
    ENV.delete("APPLY")
    ENV.delete("BACKFILL_FORCE")
  end

  test "refuses to run without PR-2 reader method or BACKFILL_FORCE" do
    ENV.delete("BACKFILL_FORCE")
    assert_raises(SystemExit) do
      capture_io { @task.invoke }
    end
  end

  test "APPLY=1 creates one desktop ScreenshotImage per Screenshot with an image and moves the blob" do
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

  test "APPLY=1 leaves Screenshots without an image untouched" do
    screenshot = screenshots(:alice_screenshot_pending)
    assert_not screenshot.image.attached?

    ENV["APPLY"] = "1"
    capture_io { @task.invoke }

    assert screenshot.reload.screenshot_images.empty?,
      "Screenshot with no image should not receive an empty ScreenshotImage placeholder"
  end

  test "re-running APPLY=1 is idempotent" do
    attach_test_image_to(screenshots(:alice_screenshot))

    ENV["APPLY"] = "1"
    capture_io { @task.invoke }
    count_after_first = ScreenshotImage.count

    @task.reenable
    capture_io { @task.invoke }

    assert_equal count_after_first, ScreenshotImage.count,
      "Second run should skip Screenshots whose desktop variant already has its blob attached"
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
