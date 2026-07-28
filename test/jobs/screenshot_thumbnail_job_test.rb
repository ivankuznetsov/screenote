# frozen_string_literal: true

require "test_helper"

class ScreenshotThumbnailJobTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  setup do
    @page = pages(:alice_page)
  end

  test "named variants have the required dimensions and aspect ratios" do
    require_vips!

    screenshot = @page.screenshots.create!(title: "Named variants")
    image = ready_image(screenshot, :desktop)

    assert_equal :processed, ScreenshotThumbnailJob.perform_now(image, image.image.blob.id)

    expected_dimensions = {
      page_card_1x: [ 480, 270 ],
      page_card_2x: [ 960, 540 ],
      project_strip: [ 240, 160 ]
    }
    expected_dimensions.each do |name, dimensions|
      processed = image.image.variant(name).processed
      rendered = Vips::Image.new_from_buffer(processed.download, "")
      assert_equal dimensions, [ rendered.width, rendered.height ]
    end
  end

  test "warms three tracked variants once for a ready desktop primary" do
    require_vips!

    screenshot = @page.screenshots.create!(title: "Ready primary")
    image = ready_image(screenshot, :desktop)

    assert_difference -> { image.image.blob.variant_records.count }, 3 do
      assert_equal :processed, ScreenshotThumbnailJob.perform_now(image, image.image.blob.id)
    end
    assert image.reload.thumbnail_variants_warmed?

    assert_no_difference -> { image.image.blob.variant_records.count } do
      assert_equal :skipped, ScreenshotThumbnailJob.perform_now(image, image.image.blob.id)
    end
  end

  test "processes every named variant and then skips an already-warmed generation" do
    screenshot = @page.screenshots.create!(title: "Warm named variants")
    image = ready_image(screenshot, :desktop)
    processed = []
    variation = Struct.new(:digest)
    variants = ScreenshotImage::THUMBNAIL_VARIANT_NAMES.map do |name|
      Object.new.tap do |variant|
        variant.define_singleton_method(:variation) { variation.new(name.to_s) }
        variant.define_singleton_method(:processed) { processed << name }
      end
    end
    image.define_singleton_method(:thumbnail_variants) { variants }
    image.define_singleton_method(:thumbnail_variants_warmed?) do
      processed.size == ScreenshotImage::THUMBNAIL_VARIANT_NAMES.size
    end

    assert_equal :processed, ScreenshotThumbnailJob.new.perform(image, image.image.blob.id)
    assert_equal ScreenshotImage::THUMBNAIL_VARIANT_NAMES, processed
    assert_equal :skipped, ScreenshotThumbnailJob.new.perform(image, image.image.blob.id)
    assert_equal ScreenshotImage::THUMBNAIL_VARIANT_NAMES, processed
  end

  test "retries a partial thumbnail generation without reprocessing tracked variants" do
    screenshot = @page.screenshots.create!(title: "Retry thumbnails")
    image = ready_image(screenshot, :desktop)
    blob = image.image.blob
    attempts = Hash.new(0)
    variants = image.thumbnail_variants.each_with_index.map do |variant, index|
      variant.define_singleton_method(:processed) do
        attempts[index] += 1
        raise StandardError, "temporary storage failure" if index == 1 && attempts[index] == 1

        blob.variant_records.create_or_find_by!(variation_digest: variation.digest)
        self
      end
      variant
    end
    image.define_singleton_method(:thumbnail_variants) { variants }

    assert_enqueued_with(job: ScreenshotThumbnailJob, args: [ image, blob.id ]) do
      ScreenshotThumbnailJob.perform_now(image, blob.id)
    end
    assert_equal 1, attempts[0]
    assert_equal 1, attempts[1]

    assert_equal :processed, ScreenshotThumbnailJob.perform_now(image, blob.id)
    assert_equal [ 1, 2, 1 ], ScreenshotImage::THUMBNAIL_VARIANT_NAMES.each_index.map { |index| attempts[index] }
    assert_equal 3, blob.variant_records.count
  end

  test "tracked records for all named digests make a repeated job a no-op" do
    screenshot = @page.screenshots.create!(title: "Tracked variants")
    image = ready_image(screenshot, :desktop)
    image.thumbnail_variants.each do |variant|
      image.image.blob.variant_records.create!(variation_digest: variant.variation.digest)
    end

    assert image.thumbnail_variants_warmed?
    assert_equal :skipped, ScreenshotThumbnailJob.perform_now(image, image.image.blob.id)
    assert_equal 3, image.image.blob.variant_records.count
  end

  test "mobile-only primary warms without warming sibling blobs" do
    require_vips!

    screenshot = @page.screenshots.create!(title: "Viewport variants")
    mobile = ready_image(screenshot, :mobile, filename: "mobile.png")

    assert_equal :processed, ScreenshotThumbnailJob.perform_now(mobile, mobile.image.blob.id)
    assert_equal 3, mobile.image.blob.variant_records.count

    desktop = ready_image(screenshot, :desktop, filename: "desktop.png")
    assert_equal :skipped, ScreenshotThumbnailJob.perform_now(mobile, mobile.image.blob.id)
    assert_equal 0, desktop.image.blob.variant_records.count

    assert_equal :processed, ScreenshotThumbnailJob.perform_now(desktop, desktop.image.blob.id)
    assert_equal 3, desktop.image.blob.variant_records.count
    assert_equal 3, mobile.image.blob.variant_records.count
  end

  test "stale replacement generation exits without warming either blob" do
    screenshot = @page.screenshots.create!(title: "Replacement")
    image = ready_image(screenshot, :desktop, filename: "old.png")
    old_blob = image.image.blob

    attach_image(image, filename: "new.png")
    image.reload

    assert_equal :skipped, ScreenshotThumbnailJob.perform_now(image, old_blob.id)
    assert_equal 0, old_blob.variant_records.count
    assert_equal 0, image.image.blob.variant_records.count
  end

  test "pending failed unattached and parent-pending images are skipped" do
    pending_screenshot = @page.screenshots.create!(title: "Pending")
    pending = attached_image(pending_screenshot, :desktop, status: :pending)

    failed_screenshot = @page.screenshots.create!(title: "Failed")
    failed = attached_image(failed_screenshot, :desktop, status: :failed)

    unattached_screenshot = @page.screenshots.create!(title: "Unattached")
    unattached = unattached_screenshot.screenshot_images.create!(
      viewport: :desktop, status: :ready, width: 100, height: 100
    )

    parent_pending_screenshot = @page.screenshots.create!(title: "Parent pending")
    parent_pending = ready_image(parent_pending_screenshot, :desktop)
    parent_pending_screenshot.screenshot_images.create!(viewport: :mobile, status: :pending)

    [
      [ pending, pending.image.blob.id ],
      [ failed, failed.image.blob.id ],
      [ unattached, 123_456 ],
      [ parent_pending, parent_pending.image.blob.id ]
    ].each do |image, blob_id|
      status = image.status
      parent_status = Screenshot.find(image.screenshot_id).status
      assert_equal :skipped, ScreenshotThumbnailJob.perform_now(image, blob_id)
      assert_equal status, image.reload.status
      assert_equal parent_status, Screenshot.find(image.screenshot_id).status
    end
  end

  test "concurrency is scoped to image and blob generation" do
    screenshot = @page.screenshots.create!(title: "Concurrency")
    image = ready_image(screenshot, :desktop, filename: "first.png")
    first_blob_id = image.image.blob.id

    first_key = ScreenshotThumbnailJob.new(image, first_blob_id).concurrency_key
    duplicate_key = ScreenshotThumbnailJob.new(image.reload, first_blob_id).concurrency_key
    attach_image(image, filename: "second.png")
    replacement_key = ScreenshotThumbnailJob.new(image.reload, image.image.blob.id).concurrency_key

    assert_equal first_key, duplicate_key
    assert_not_equal first_key, replacement_key
  end

  private

  def ready_image(screenshot, viewport, filename: "#{viewport}.png")
    attached_image(screenshot, viewport, status: :ready, filename:)
  end

  def attached_image(screenshot, viewport, status:, filename: "#{viewport}.png")
    image = screenshot.screenshot_images.build(
      viewport: viewport,
      status: status,
      width: 100,
      height: 100
    )
    attach_image(image, filename:)
    image.save!
    image
  end

  def attach_image(image, filename:)
    image.image.attach(
      io: StringIO.new(File.binread(Rails.root.join("test/fixtures/files/test_image.png"))),
      filename: filename,
      content_type: "image/png"
    )
  end
end
