# frozen_string_literal: true

# Warms the delivery variants for a submitted attachment. Nothing enqueues this
# for a draft, and an authenticated GET never invokes it: an unwarmed variant
# stays unavailable until a run of this job produces it. Claiming a batch
# enqueues one of these per attachment; reconciliation re-enqueues the ones
# whose variants are still missing, which is why every pass re-resolves both
# ownership and the blob generation it was asked to warm.
class ImageAttachmentThumbnailJob < ApplicationJob
  ThumbnailProcessingError = Class.new(StandardError)

  queue_as :default

  retry_on ThumbnailProcessingError, wait: 10.seconds, attempts: 3
  discard_on ActiveJob::DeserializationError

  limits_concurrency key: ->(attachment, blob_id) {
    "#{attachment.to_global_id}/blob/#{blob_id}"
  }, duration: 10.minutes, on_conflict: :discard

  def perform(attachment, blob_id)
    attachment.reload
    return :skipped unless warmable?(attachment, blob_id)
    return :skipped if attachment.thumbnail_variants_warmed?

    ImageAttachment::THUMBNAIL_VARIANT_NAMES.each do |name|
      attachment.reload
      return :skipped unless warmable?(attachment, blob_id)
      next if attachment.thumbnail_variant_ready?(name)

      begin
        ImageDecoding::Guard.synchronize { attachment.image.variant(name).processed }
      rescue StandardError => error
        raise ThumbnailProcessingError, "attachment variant processing failed", cause: error
      end
    end

    :processed
  rescue ActiveRecord::RecordNotFound
    :skipped
  end

  private

  # Re-resolves ownership on every pass so a job queued before a removal, a
  # rollback, or a replacement can never warm bytes that no message owns.
  def warmable?(attachment, blob_id)
    attachment.submitted? &&
      attachment.state_ready? &&
      attachment.image.attached? &&
      attachment.image_attachment.blob_id.to_s == blob_id.to_s &&
      attachment.parent.present?
  end
end
