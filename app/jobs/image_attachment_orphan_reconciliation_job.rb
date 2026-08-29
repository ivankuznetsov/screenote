# frozen_string_literal: true

# Catches submitted attachment rows whose message no longer resolves because a
# delete bypassed the Rails callbacks — a database cascade, a bulk delete, or a
# future code path. Without this, those primary blobs and their derivatives
# would stay in the storage service forever.
class ImageAttachmentOrphanReconciliationJob < ApplicationJob
  BATCH_LIMIT = 500

  queue_as :default

  limits_concurrency key: -> { "image-attachment-orphan-reconciliation" },
    duration: 30.minutes,
    on_conflict: :discard

  def perform(limit: BATCH_LIMIT)
    purged = 0

    orphan_ids(limit).each do |id|
      purged += 1 if purge(id)
    rescue StandardError => error
      Screenote::Monitoring.notify(
        "Image attachment orphan reconciliation failed",
        context: { image_attachment_id: id, error_class: error.class.name }
      )
    end

    if purged.positive?
      Screenote::Monitoring.notify(
        "Image attachment orphans reconciled",
        context: { purged: purged }
      )
    end

    purged
  end

  private

  def orphan_ids(limit)
    ImageAttachment
      .submitted
      .left_outer_joins(:annotation, :annotation_comment)
      .where(annotations: { id: nil }, annotation_comments: { id: nil })
      .order(:id)
      .limit(limit)
      .pluck(:id)
  end

  def purge(id)
    ImageAttachment.transaction do
      attachment = ImageAttachment.lock.find_by(id: id)
      next false unless attachment
      # Re-resolve inside the lock: a row whose parent exists again, or which
      # became a draft, must never be purged by a stale candidate scan.
      next false unless attachment.submitted? && attachment.parent.nil?

      attachment.destroy!
      true
    end
  end
end
