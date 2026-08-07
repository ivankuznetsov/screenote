# frozen_string_literal: true

require "test_helper"

class ScreenshotProcessingReconciliationTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  setup do
    @screenshot = pages(:alice_page).screenshots.create!(title: "Reconciliation")
    @image = @screenshot.screenshot_images.create!(viewport: :desktop)
    @image.image.attach(
      io: StringIO.new(file_fixture("test_image.png").binread),
      filename: "reconcile.png",
      content_type: "image/png"
    )
    clear_enqueued_jobs
  end

  test "reconciliation completes a committed image after dimension enqueue fails" do
    require_vips!
    with_class_method_stub(ScreenshotDimensionJob, :perform_later, ->(*) { raise ActiveJob::EnqueueError, "queue unavailable" }) do
      assert_nothing_raised { @image.ensure_dimension_processing }
    end

    assert @image.reload.status_pending?
    assert @image.image.attached?

    assert_equal 1, ReconcileScreenshotProcessingJob.perform_now
    assert @image.reload.status_ready?
    assert @image.thumbnail_variants_warmed?
  end

  test "reconciliation resumes thumbnail work after downstream enqueue fails" do
    require_vips!
    with_class_method_stub(ScreenshotThumbnailJob, :perform_later, ->(*) { raise ActiveJob::EnqueueError, "queue unavailable" }) do
      assert_nothing_raised do
        ScreenshotDimensionJob.perform_now(@image, @image.image.blob.id)
      end
    end

    assert @image.reload.status_ready?
    assert_not @image.thumbnail_variants_warmed?

    assert_equal 1, ReconcileScreenshotProcessingJob.perform_now
    assert @image.reload.thumbnail_variants_warmed?
  end

  test "reconciliation is idempotent once the processing graph is terminal" do
    require_vips!
    assert_equal 1, ReconcileScreenshotProcessingJob.perform_now
    counts = [ ActiveStorage::Blob.count, ActiveStorage::Attachment.count,
      ActiveStorage::VariantRecord.count ]

    assert_no_enqueued_jobs do
      assert_equal 0, ReconcileScreenshotProcessingJob.perform_now
    end
    assert_equal counts, [ ActiveStorage::Blob.count, ActiveStorage::Attachment.count,
      ActiveStorage::VariantRecord.count ]
  end

  private

  def with_class_method_stub(target, method_name, replacement)
    original = target.method(method_name)
    target.define_singleton_method(method_name, replacement)
    yield
  ensure
    target.define_singleton_method(method_name, original)
  end
end
