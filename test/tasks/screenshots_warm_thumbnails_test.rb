# frozen_string_literal: true

require "test_helper"
require "rake"

class ScreenshotsWarmThumbnailsTest < ActiveSupport::TestCase
  setup do
    ScreenshotImage.delete_all
    Rails.application.load_tasks unless Rake::Task.task_defined?("screenshots:warm_thumbnails")
    @image = ready_image
  end

  teardown do
    ENV.delete("APPLY")
    ENV.delete("BATCH_SIZE")
  end

  test "warm_thumbnails is a dry-run by default with exact counters" do
    output, = capture_io { invoke_task }

    assert_includes output, "[DRY-RUN]"
    assert_includes output, "{candidates: 1, skipped: 0, processed: 0, failed: 0}"
    assert_equal 0, @image.image.blob.variant_records.count
  end

  test "warm_thumbnails apply processes once then reports the existing variants as skipped" do
    require_vips!
    ENV["APPLY"] = "1"
    ENV["BATCH_SIZE"] = "1"

    first_output, = capture_io { invoke_task }
    assert_includes first_output, "[APPLY]"
    assert_includes first_output, "{candidates: 1, skipped: 0, processed: 1, failed: 0}"
    assert_equal 3, @image.image.blob.variant_records.count

    second_output, = capture_io { invoke_task }
    assert_includes second_output, "{candidates: 0, skipped: 1, processed: 0, failed: 0}"
    assert_equal 3, @image.image.blob.variant_records.count
  end

  test "warm_thumbnails reports pre-existing tracked variants as skipped" do
    @image.thumbnail_variants.each do |variant|
      @image.image.blob.variant_records.create!(variation_digest: variant.variation.digest)
    end

    output, = capture_io { invoke_task }

    assert_includes output, "{candidates: 0, skipped: 1, processed: 0, failed: 0}"
    assert_equal 3, @image.image.blob.variant_records.count
  end

  test "apply counts processing failures and continues" do
    ENV["APPLY"] = "1"
    @image.image.blob.update_column(:content_type, "text/plain")

    output, = capture_io { invoke_task }

    assert_includes output, "{candidates: 0, skipped: 0, processed: 0, failed: 1}"
    assert_includes output, "ActiveStorage::InvariableError"
    assert @image.reload.status_ready?
    assert @image.screenshot.reload.ready?
  end

  private

  def invoke_task
    task = Rake::Task["screenshots:warm_thumbnails"]
    task.reenable
    task.invoke
  end

  def ready_image
    screenshot = pages(:alice_page).screenshots.create!(title: "Warm task")
    image = screenshot.screenshot_images.build(
      viewport: :desktop,
      status: :ready,
      width: 100,
      height: 100
    )
    image.image.attach(
      io: StringIO.new(File.binread(Rails.root.join("test/fixtures/files/test_image.png"))),
      filename: "task.png",
      content_type: "image/png"
    )
    image.save!
    image
  end
end
