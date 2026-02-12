# frozen_string_literal: true

class ScreenshotDimensionJob < ApplicationJob
  def perform(screenshot)
    return unless screenshot.image.attached?

    screenshot.image.blob.analyze unless screenshot.image.blob.analyzed?

    metadata = screenshot.image.blob.metadata
    width = metadata["width"]
    height = metadata["height"]

    if width.present? && height.present?
      screenshot.update!(width: width, height: height, status: :ready)
    else
      screenshot.update!(status: :failed)
    end
  end
end
