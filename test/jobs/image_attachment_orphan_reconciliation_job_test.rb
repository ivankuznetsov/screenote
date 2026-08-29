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
    result = ImageAttachments::ClaimBatch.call(batch: batch, user: @user, project: @project) do
      screenshots(:alice_screenshot).annotations.create!(
        user: @user, x_percent: 1, y_percent: 1, comment: "Posted"
      )
    end
    result.attachments.sole
  end
end
