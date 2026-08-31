# frozen_string_literal: true

# Reclaims abandoned composer drafts. Candidate scans are bounded, and each
# batch is locked and rechecked before anything is destroyed so a pass that
# overlaps a live submission cannot take bytes away from a message.
class ImageAttachmentDraftCleanupJob < ApplicationJob
  BATCH_LIMIT = 500

  queue_as :default

  limits_concurrency key: -> { "image-attachment-draft-cleanup" },
    duration: 30.minutes,
    on_conflict: :discard

  def perform(limit: BATCH_LIMIT)
    now = Time.current
    removed = 0

    candidate_ids(now, limit).each do |id|
      removed += 1 if reclaim(id, now)
    rescue StandardError => error
      Screenote::Monitoring.notify(
        "Image attachment draft cleanup failed",
        context: { image_attachment_batch_id: id, error_class: error.class.name }
      )
    end

    removed
  end

  private

  def candidate_ids(now, limit)
    ImageAttachmentBatch.outstanding.expired(now).order(:id).limit(limit).pluck(:id)
  end

  def reclaim(id, now)
    ImageAttachmentBatch.transaction do
      batch = ImageAttachmentBatch.lock.find_by(id: id)
      next false unless batch
      next false unless batch.state_open? && batch.expired?(now)

      # destroy cascades to the attachment rows, whose Active Storage lifecycle
      # purges the primary blob together with every derivative.
      batch.image_attachments.ordered.lock.to_a
      batch.destroy!
      true
    end
  end
end
