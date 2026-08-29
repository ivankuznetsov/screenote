# frozen_string_literal: true

require "test_helper"

class ImageAttachmentDraftCleanupJobTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  setup do
    require_vips!
    @user = users(:alice)
    @project = projects(:alice_project)
  end

  test "reclaims an abandoned draft and purges its bytes" do
    batch = build_batch
    attachment = ingest_image(batch: batch)
    blob = attachment.image.blob
    batch.update_columns(last_activity_at: 25.hours.ago, expires_at: 1.hour.ago)

    assert_equal 1, perform_enqueued_jobs { ImageAttachmentDraftCleanupJob.perform_now }

    assert_not ImageAttachmentBatch.exists?(batch.id)
    assert_not ImageAttachment.exists?(attachment.id)
    assert_not ActiveStorage::Blob.exists?(blob.id)
  end

  test "leaves live drafts alone" do
    batch = build_batch
    ingest_image(batch: batch)

    assert_equal 0, ImageAttachmentDraftCleanupJob.perform_now
    assert ImageAttachmentBatch.exists?(batch.id)
  end

  test "never takes bytes away from a posted message" do
    batch = build_batch
    attachment = ingest_image(batch: batch)
    ImageAttachments::ClaimBatch.call(batch: batch, user: @user, project: @project, parent_type: Annotation) do
      screenshots(:alice_screenshot).annotations.create!(
        user: @user, x_percent: 1, y_percent: 1, comment: "Posted"
      )
    end
    batch.update_columns(last_activity_at: 25.hours.ago, expires_at: 1.hour.ago)

    assert_equal 0, ImageAttachmentDraftCleanupJob.perform_now

    assert ImageAttachment.exists?(attachment.id)
    assert attachment.reload.image.attached?
  end

  test "candidate scans are bounded" do
    3.times do
      build_batch.update_columns(last_activity_at: 25.hours.ago, expires_at: 1.hour.ago)
    end

    assert_equal 2, ImageAttachmentDraftCleanupJob.perform_now(limit: 2)
    assert_equal 1, ImageAttachmentBatch.count
  end
end
