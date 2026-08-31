# frozen_string_literal: true

require "test_helper"

class ImageAttachmentOrphanReconciliationJobTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  setup do
    require_vips!
    @user = users(:alice)
    @project = projects(:alice_project)
  end

  test "purges a submitted row whose message was deleted without callbacks" do
    attachment = submitted_attachment
    blob = attachment.image.blob
    delete_parent_bypassing_callbacks(attachment)

    assert_equal 1, perform_enqueued_jobs { ImageAttachmentOrphanReconciliationJob.perform_now }

    assert_not ImageAttachment.exists?(attachment.id)
    assert_not ActiveStorage::Blob.exists?(blob.id)
  end

  test "never purges a row whose message still resolves" do
    attachment = submitted_attachment

    assert_equal 0, ImageAttachmentOrphanReconciliationJob.perform_now
    assert ImageAttachment.exists?(attachment.id)
  end

  test "never purges a live draft" do
    batch = build_batch
    attachment = ingest_image(batch: batch)

    assert_equal 0, ImageAttachmentOrphanReconciliationJob.perform_now
    assert ImageAttachment.exists?(attachment.id)
  end

  test "reconciliation is idempotent" do
    attachment = submitted_attachment
    delete_parent_bypassing_callbacks(attachment)

    assert_equal 1, ImageAttachmentOrphanReconciliationJob.perform_now
    assert_equal 0, ImageAttachmentOrphanReconciliationJob.perform_now
  end

  # A lost `perform_later` at claim time would otherwise leave a posted gallery
  # on its stable placeholder until the process restarted.
  test "re-enqueues warming for a submitted attachment whose variants are missing" do
    attachment = submitted_attachment
    clear_enqueued_jobs

    assert_not attachment.thumbnail_variants_warmed?
    assert_enqueued_with(job: ImageAttachmentThumbnailJob) { ImageAttachmentOrphanReconciliationJob.perform_now }
  end

  test "re-enqueueing stops once the variants exist" do
    attachment = submitted_attachment
    perform_enqueued_jobs(only: ImageAttachmentThumbnailJob)

    assert attachment.reload.thumbnail_variants_warmed?
    assert_no_enqueued_jobs(only: ImageAttachmentThumbnailJob) do
      ImageAttachmentOrphanReconciliationJob.perform_now
    end
  end

  test "never warms a draft" do
    batch = build_batch
    ingest_image(batch: batch)
    clear_enqueued_jobs

    assert_no_enqueued_jobs(only: ImageAttachmentThumbnailJob) do
      ImageAttachmentOrphanReconciliationJob.perform_now
    end
  end

  test "variant reconciliation selects at most the requested missing rows" do
    2.times { submitted_attachment }
    clear_enqueued_jobs

    ImageAttachmentOrphanReconciliationJob.perform_now(limit: 1)

    assert_enqueued_jobs 1, only: ImageAttachmentThumbnailJob
  end

  # A provider delete that failed deliberately leaves the blob row behind so the
  # key stays durable. Retrying it is this pass's job.
  test "retries an unattached blob a failed provider delete left behind" do
    attachment = submitted_attachment
    blob = attachment.image.blob
    attachment.image.detach
    blob.update_columns(created_at: (ImageAttachmentOrphanReconciliationJob::UNATTACHED_GRACE + 1.hour).ago)

    ImageAttachmentOrphanReconciliationJob.perform_now

    assert_not ActiveStorage::Blob.exists?(blob.id)
  end

  test "never reclaims a blob an in-flight upload may still be about to attach" do
    attachment = submitted_attachment
    blob = attachment.image.blob
    attachment.image.detach

    ImageAttachmentOrphanReconciliationJob.perform_now

    assert ActiveStorage::Blob.exists?(blob.id)
  end

  test "never reclaims an unattached blob that belongs to another subsystem" do
    blob = ActiveStorage::Blob.create_and_upload!(
      io: StringIO.new(image_bytes), filename: "screenshot.png", content_type: "image/png"
    )
    blob.update_columns(created_at: (ImageAttachmentOrphanReconciliationJob::UNATTACHED_GRACE + 1.hour).ago)

    ImageAttachmentOrphanReconciliationJob.perform_now

    assert ActiveStorage::Blob.exists?(blob.id)
  end

  private

  # Foreign keys make this unreachable through the application, which is the
  # point: reconciliation is the backstop for a future deletion path that skips
  # the Rails callbacks entirely.
  def delete_parent_bypassing_callbacks(attachment)
    ImageAttachment.connection.disable_referential_integrity do
      Annotation.where(id: attachment.annotation_id).delete_all
    end
  end

  def submitted_attachment
    batch = build_batch
    ingest_image(batch: batch)
    result = ImageAttachments::ClaimBatch.call(batch: batch, user: @user, project: @project, parent_type: Annotation) do
      screenshots(:alice_screenshot).annotations.create!(
        user: @user, x_percent: 1, y_percent: 1, comment: "Posted"
      )
    end
    result.attachments.sole
  end
end
