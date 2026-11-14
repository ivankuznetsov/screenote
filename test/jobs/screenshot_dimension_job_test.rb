# frozen_string_literal: true

require "test_helper"

class ScreenshotDimensionJobTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  setup do
    @page = pages(:alice_page)
  end

  test "sets dimensions and status to ready for ScreenshotImage with valid image" do
    require_vips!

    screenshot = @page.screenshots.create!(title: "Dimension Test")
    si = screenshot.screenshot_images.create!(viewport: :desktop)
    si.image.attach(
      io: File.open(Rails.root.join("test/fixtures/files/test_image.png")),
      filename: "test.png", content_type: "image/png"
    )

    blob_id = si.image.blob.id
    assert_enqueued_with(job: ScreenshotThumbnailJob, args: [ si, blob_id ]) do
      assert_equal :processed, ScreenshotDimensionJob.perform_now(si, blob_id)
    end

    si.reload
    assert si.status_ready?
    assert si.width.present?
    assert si.height.present?
  end

  test "warming targets the desktop primary after the final mobile dimension finishes" do
    screenshot = @page.screenshots.create!(title: "Primary thumbnail")
    desktop = ready_image(screenshot, :desktop, filename: "desktop.png")
    mobile = screenshot.screenshot_images.create!(viewport: :mobile)
    attach_test_image(mobile, filename: "mobile.png")
    screenshot.reload
    assert screenshot.pending?

    job = job_with_dimensions
    clear_enqueued_jobs
    assert_enqueued_with(
      job: ScreenshotThumbnailJob,
      args: [ desktop, desktop.image.blob.id ]
    ) do
      job.perform(mobile, mobile.image.blob.id)
    end

    assert_equal 1, enqueued_jobs.count { |job| job[:job] == ScreenshotThumbnailJob }
    assert screenshot.reload.ready?
  end

  test "mobile-only screenshots warm their mobile primary" do
    screenshot = @page.screenshots.create!(title: "Mobile thumbnail")
    mobile = screenshot.screenshot_images.create!(viewport: :mobile)
    attach_test_image(mobile, filename: "mobile.png")

    assert_enqueued_with(
      job: ScreenshotThumbnailJob,
      args: [ mobile, mobile.image.blob.id ]
    ) do
      job_with_dimensions.perform(mobile, mobile.image.blob.id)
    end
  end

  test "same blob jobs share a concurrency key but replacement blob jobs do not" do
    screenshot = @page.screenshots.create!(title: "Concurrency generation")
    si = screenshot.screenshot_images.create!(viewport: :desktop)
    attach_test_image(si, filename: "first.png")
    first_blob_id = si.image.blob.id

    first_key = ScreenshotDimensionJob.new(si, first_blob_id).concurrency_key
    duplicate_key = ScreenshotDimensionJob.new(si.reload, first_blob_id).concurrency_key

    attach_test_image(si, filename: "replacement.png")
    replacement_blob_id = si.image.blob.id
    replacement_key = ScreenshotDimensionJob.new(si.reload, replacement_blob_id).concurrency_key

    assert_equal first_key, duplicate_key
    assert_not_equal first_key, replacement_key
  end

  test "does not apply stale dimensions when the attachment is replaced during analysis" do
    screenshot = @page.screenshots.create!(title: "Stale generation")
    si = screenshot.screenshot_images.create!(viewport: :desktop)
    attach_test_image(si, filename: "old.png")
    old_blob_id = si.image.blob.id
    job = ScreenshotDimensionJob.new
    replace_attachment = method(:attach_test_image)

    analyze_and_replace = lambda do |_blob|
      replace_attachment.call(si, filename: "new.png")
      si.update!(status: :pending, width: nil, height: nil)
      { "width" => 640, "height" => 480 }
    end

    job.define_singleton_method(:analyze_blob, analyze_and_replace)
    job.perform(si, old_blob_id)

    si.reload
    assert_not_equal old_blob_id, si.image.blob.id
    assert si.status_pending?
    assert_nil si.width
    assert_nil si.height
  end

  test "skips already ready ScreenshotImage" do
    si = screenshot_images(:alice_screenshot_desktop)
    original_width = si.width

    assert_equal :skipped, ScreenshotDimensionJob.perform_now(si, 123_456)

    assert_equal original_width, si.reload.width
  end

  test "returns early when ScreenshotImage has no image attached" do
    screenshot = @page.screenshots.create!(title: "No image")
    si = screenshot.screenshot_images.create!(viewport: :desktop)

    assert_equal :skipped, ScreenshotDimensionJob.perform_now(si, 123_456)
    assert si.reload.status_pending?
  end

  test "leaves a replaced attachment to the job enqueued for its blob" do
    screenshot = @page.screenshots.create!(title: "Replaced before start")
    si = screenshot.screenshot_images.create!(viewport: :desktop)
    attach_test_image(si, filename: "old.png")
    old_blob_id = si.image.blob.id
    attach_test_image(si, filename: "new.png")

    assert_equal :skipped, job_with_dimensions.perform(si.reload, old_blob_id)
    assert si.reload.status_pending?
  end

  private

  def attach_test_image(screenshot_image, filename:)
    screenshot_image.image.attach(
      io: File.open(Rails.root.join("test/fixtures/files/test_image.png")),
      filename: filename,
      content_type: "image/png"
    )
  end

  def ready_image(screenshot, viewport, filename:)
    screenshot_image = screenshot.screenshot_images.build(
      viewport: viewport,
      status: :ready,
      width: 100,
      height: 100
    )
    attach_test_image(screenshot_image, filename:)
    screenshot_image.save!
    screenshot_image
  end

  def job_with_dimensions
    ScreenshotDimensionJob.new.tap do |job|
      job.define_singleton_method(:analyze_blob) do |_blob|
        { "width" => 100, "height" => 100 }
      end
    end
  end
end
