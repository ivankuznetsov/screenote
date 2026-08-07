# frozen_string_literal: true

require "test_helper"

class ScreenshotDimensionJobTransactionTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  self.use_transactional_tests = false

  setup do
    @previous_enqueue_after_commit = ScreenshotDimensionJob.enqueue_after_transaction_commit
    ScreenshotDimensionJob.enqueue_after_transaction_commit = true
    clear_enqueued_jobs
  end

  teardown do
    ScreenshotDimensionJob.enqueue_after_transaction_commit = @previous_enqueue_after_commit
    clear_enqueued_jobs
  end

  test "enqueues replacement processing exactly once after the outer transaction commits" do
    image = screenshot_images(:alice_screenshot_desktop)
    blob_id = 123_456

    ActiveRecord::Base.transaction do
      ScreenshotDimensionJob.perform_later(image, blob_id)

      assert_empty enqueued_jobs
    end

    assert_enqueued_jobs 1, only: ScreenshotDimensionJob
    assert_enqueued_with(job: ScreenshotDimensionJob, args: [ image, blob_id ])
  end

  test "does not enqueue replacement processing when the outer transaction rolls back" do
    image = screenshot_images(:alice_screenshot_desktop)
    blob_id = 123_456

    ActiveRecord::Base.transaction do
      ScreenshotDimensionJob.perform_later(image, blob_id)
      raise ActiveRecord::Rollback
    end

    assert_no_enqueued_jobs only: ScreenshotDimensionJob
  end
end
