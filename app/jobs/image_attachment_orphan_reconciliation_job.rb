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
  # An upload stages its blob before it attaches it, so a freshly created
  # unattached blob may simply be mid-request.
  UNATTACHED_GRACE = 6.hours

  queue_as :default

  limits_concurrency key: -> { "image-attachment-orphan-reconciliation" },
    duration: 30.minutes,
    on_conflict: :discard

  def perform(limit: BATCH_LIMIT)
    purged = purge_orphans(limit)
    rewarmed = rewarm_variants(limit)
    reclaimed = reclaim_unattached_blobs(limit)

    if purged.positive? || rewarmed.positive? || reclaimed.positive?
      Screenote::Monitoring.notify(
        "Image attachments reconciled",
        context: { purged: purged, rewarmed: rewarmed, reclaimed: reclaimed }
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

    unwarmed_candidates(limit).each do |attachment|
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

  # A JOIN plus GROUP BY has to build every group before the LIMIT can drop any
  # of them, so the previous query still touched every submitted attachment ever
  # posted on each hourly pass. `NOT EXISTS` per digest is a per-row predicate
  # instead: the planner walks `image_attachments` in ID order, probes the
  # variant-record index, and stops as soon as `limit` candidates are found.
  def unwarmed_candidates(limit)
    ids = ImageAttachment
      .submitted
      .state_ready
      .joins(:image_blob)
      .where(missing_any_variant)
      .order(:id)
      .limit(limit)
      .pluck(:id)

    ImageAttachment.where(id: ids).includes(ImageAttachment::RENDER_PRELOAD).order(:id)
  end

  def missing_any_variant
    thumbnail_variant_digests
      .map { |digest| ActiveStorage::VariantRecord.where(blob_id: ActiveStorage::Blob.arel_table[:id], variation_digest: digest).arel.exists.not }
      .reduce(:or)
  end

  def thumbnail_variant_digests
    ImageAttachment.attachment_reflections.fetch("image").named_variants
      .values
      .map { |variant| ActiveStorage::Variation.wrap(variant.transformations).digest }
  end

  # Where a provider delete failed, the blob row is deliberately left behind so
  # the key stays durable. Retrying it is this pass's job. Only blobs this
  # feature staged are considered — the server generates their names — and only
  # once they are old enough that no in-flight upload can still be about to
  # attach them.
  def reclaim_unattached_blobs(limit)
    reclaimed = 0

    ActiveStorage::Blob
      .unattached
      .where("active_storage_blobs.filename LIKE ?", "image-attachment-%")
      .where(created_at: ...UNATTACHED_GRACE.ago)
      .order(:id)
      .limit(limit)
      .each { |blob| reclaimed += 1 if ImageAttachments::PurgeBlob.call(blob) }

    reclaimed
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
