# frozen_string_literal: true

class ScreenshotDimensionJob < ApplicationJob
  def perform(screenshot)
    return if screenshot.ready?

    unless screenshot.image.attached?
      Rails.logger.warn("ScreenshotDimensionJob: Screenshot #{screenshot.id} has no attached image")
      return
    end

    screenshot.image.blob.analyze unless screenshot.image.blob.analyzed?

    metadata = screenshot.image.blob.metadata
    width = metadata["width"]
    height = metadata["height"]

    if width.present? && height.present?
      screenshot.update!(width: width, height: height, status: :ready)
    else
      Honeybadger.notify("Screenshot dimension extraction failed",
        context: { screenshot_id: screenshot.id, metadata: metadata })
      screenshot.update!(status: :failed)
    end
  end
end
