# frozen_string_literal: true

require "test_helper"
require "rake"

# Smoke test that the rake tasks correctly invoke their services.
# Full behavior coverage lives in test/services/screenshot_image_*_service_test.rb.
class ScreenshotsBackfillViewportsTest < ActiveSupport::TestCase
  setup do
    ScreenshotImage.delete_all
    Rails.application.load_tasks unless Rake::Task.task_defined?("screenshots:backfill_viewports")
  end

  teardown do
    ENV.delete("APPLY")
  end

  test "backfill_viewports APPLY=1 invokes the service" do
    screenshot = screenshots(:alice_screenshot)
    attach_test_image(screenshot)

    ENV["APPLY"] = "1"
    task = Rake::Task["screenshots:backfill_viewports"]
    task.reenable
    capture_io { task.invoke }

    assert screenshot.reload.screenshot_images.find_by(viewport: :desktop)&.image&.attached?
  end

  test "rollback_backfill APPLY=1 invokes the service" do
    screenshot = screenshots(:alice_screenshot)
    screenshot.image.purge if screenshot.image.attached?
    si = ScreenshotImage.create!(screenshot: screenshot, viewport: :desktop)
    attach_test_image(si)

    ENV["APPLY"] = "1"
    task = Rake::Task["screenshots:rollback_backfill"]
    task.reenable
    capture_io { task.invoke }

    assert screenshot.reload.image.attached?
    assert_not ScreenshotImage.exists?(si.id)
  end

  private

  def attach_test_image(record)
    record.image.attach(
      io: StringIO.new(File.binread(Rails.root.join("test/fixtures/files/test_image.png"))),
      filename: "test.png", content_type: "image/png"
    )
  end
end
