# frozen_string_literal: true

class ScreenshotThumbnailJob < ApplicationJob
  ThumbnailProcessingError = Class.new(StandardError)

  retry_on ThumbnailProcessingError, wait: 10.seconds, attempts: 3

  limits_concurrency key: ->(screenshot_image, blob_id) {
    "#{screenshot_image.to_global_id}/blob/#{blob_id}"
  }, duration: 10.minutes, on_conflict: :discard

  def perform(screenshot_image, blob_id)
    screenshot_image.reload
    return :skipped unless screenshot_image.thumbnail_warmable?(blob_id:)
    return :skipped if screenshot_image.thumbnail_variants_warmed?

    variants = screenshot_image.thumbnail_variants
    warmed_digests = screenshot_image.image.blob.variant_records
      .where(variation_digest: variants.map { |variant| variant.variation.digest })
      .pluck(:variation_digest)

    variants.each do |variant|
      screenshot_image.reload
      return :skipped unless screenshot_image.thumbnail_warmable?(blob_id:)
      next if warmed_digests.include?(variant.variation.digest)

      begin
        variant.processed
      rescue StandardError => error
        raise ThumbnailProcessingError, "thumbnail variant processing failed", cause: error
      end
    end

    :processed
  end
end
