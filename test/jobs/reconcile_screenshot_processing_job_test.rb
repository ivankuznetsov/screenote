# frozen_string_literal: true

require "test_helper"

class ReconcileScreenshotProcessingJobTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  test "startup reconciliation is accepted only after the queue confirms enqueue" do
    job = nil
    assert_enqueued_with(job: ReconcileScreenshotProcessingJob) do
      job = ReconcileScreenshotProcessingJob.enqueue_for_startup!
    end

    assert job.successfully_enqueued?
  end

  test "startup reconciliation accepts a concurrency-discarded duplicate" do
    discarded_job = ReconcileScreenshotProcessingJob.new

    returned_job = with_class_method_stub(
      ReconcileScreenshotProcessingJob,
      :perform_later,
      lambda do |&block|
        block.call(discarded_job)
        false
      end
    ) do
      ReconcileScreenshotProcessingJob.enqueue_for_startup!
    end

    assert_same discarded_job, returned_job
    assert_not returned_job.successfully_enqueued?
    assert_nil returned_job.enqueue_error
  end

  test "startup reconciliation propagates a real queue error" do
    failed_job = ReconcileScreenshotProcessingJob.new
    failed_job.enqueue_error = ActiveJob::EnqueueError.new("queue unavailable")

    error = with_class_method_stub(
      ReconcileScreenshotProcessingJob,
      :perform_later,
      lambda do |&block|
        block.call(failed_job)
        false
      end
    ) do
      assert_raises(ActiveJob::EnqueueError) do
        ReconcileScreenshotProcessingJob.enqueue_for_startup!
      end
    end

    assert_equal "queue unavailable", error.message
  end

  test "visits only images that still have processing work" do
    page = pages(:alice_page)
    cold = ready_image(page.screenshots.create!(title: "Cold"))
    warm = ready_image(page.screenshots.create!(title: "Warm"))
    warm.thumbnail_variants.each do |variant|
      warm.image.blob.variant_records.create!(variation_digest: variant.variation.digest)
    end

    visited = []
    record_visit = lambda do |image:|
      visited << image.id
      :skipped
    end
    with_class_method_stub(ScreenshotImages::EnsureProcessing, :call, record_visit) do
      assert_equal 0, ReconcileScreenshotProcessingJob.perform_now
    end

    assert_includes visited, cold.id
    assert_not_includes visited, warm.id
  end

  private

  def ready_image(screenshot)
    image = screenshot.screenshot_images.build(viewport: :desktop, status: :ready, width: 100, height: 100)
    image.image.attach(
      io: StringIO.new(file_fixture("test_image.png").binread),
      filename: "ready.png",
      content_type: "image/png"
    )
    image.save!
    image
  end

  def with_class_method_stub(target, method_name, replacement)
    original = target.method(method_name)
    target.define_singleton_method(method_name, replacement)
    yield
  ensure
    target.define_singleton_method(method_name, original)
  end
end
