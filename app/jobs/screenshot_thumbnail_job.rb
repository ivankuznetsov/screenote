# frozen_string_literal: true

class ScreenshotThumbnailJob < ApplicationJob
  limits_concurrency key: ->(screenshot_image, blob_id) {
    "#{screenshot_image.to_global_id}/blob/#{blob_id}"
  }, duration: 10.minutes, on_conflict: :discard

  def perform(screenshot_image, blob_id)
    screenshot_image.reload
    return :skipped unless screenshot_image.thumbnail_warmable?(blob_id:)
    return :skipped if screenshot_image.thumbnail_variants_warmed?

    screenshot_image.thumbnail_variants.each do |variant|
      screenshot_image.reload
      return :skipped unless screenshot_image.thumbnail_warmable?(blob_id:)

      variant.processed
    end

    :processed
  end
end
