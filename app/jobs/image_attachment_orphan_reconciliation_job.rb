# frozen_string_literal: true

# Reconciles submitted attachments against what the storage service actually
# holds, in both directions.
#
# Rows whose message no longer resolves — a database cascade, a bulk delete, or
# a future code path that bypassed the Rails callbacks — are purged, so their
# primary blobs and derivatives do not stay in the storage service forever.
# Rows whose delivery variants were never produced are re-enqueued, so a claim
# whose `perform_later` was lost does not leave a posted gallery on its stable
# placeholder until the process restarts.
class ImageAttachmentOrphanReconciliationJob < ApplicationJob
  BATCH_LIMIT = 500

  queue_as :default

  limits_concurrency key: -> { "image-attachment-orphan-reconciliation" },
    duration: 30.minutes,
    on_conflict: :discard

  def perform(limit: BATCH_LIMIT)
    purged = purge_orphans(limit)
    rewarmed = rewarm_variants(limit)

    if purged.positive? || rewarmed.positive?
      Screenote::Monitoring.notify(
        "Image attachments reconciled",
        context: { purged: purged, rewarmed: rewarmed }
      )
    end

    purged
  end

  private

  def purge_orphans(limit)
    purged = 0

    orphan_ids(limit).each do |id|
      purged += 1 if purge(id)
    rescue StandardError => error
      Screenote::Monitoring.notify(
        "Image attachment orphan reconciliation failed",
        context: { image_attachment_id: id, error_class: error.class.name }
      )
    end

    purged
  end

  # Re-enqueueing is idempotent and generation aware: the job is keyed on the
  # attachment together with the exact blob it was asked to warm, and it skips
  # a row whose variants already exist or whose bytes have since been replaced.
  # Warming state is read from preloaded variant records, so this never
  # processes an image itself.
  def rewarm_variants(limit)
    enqueued = 0

    unwarmed_candidates.find_each do |attachment|
      break if enqueued >= limit
      next if attachment.thumbnails_renderable?

      ImageAttachmentThumbnailJob.perform_later(attachment, attachment.image.blob.id)
      enqueued += 1
    rescue StandardError => error
      Screenote::Monitoring.notify(
        "Image attachment variant reconciliation failed",
        context: { image_attachment_id: attachment.id, error_class: error.class.name }
      )
    end

    enqueued
  end

  def unwarmed_candidates
    ImageAttachment.submitted.state_ready.includes(ImageAttachment::RENDER_PRELOAD).order(:id)
  end

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
