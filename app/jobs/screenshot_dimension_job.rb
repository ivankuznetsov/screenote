# frozen_string_literal: true

class ScreenshotDimensionJob < ApplicationJob
  def perform(screenshot)
    return unless screenshot.image.attached?

    screenshot.image.blob.analyze unless screenshot.image.blob.analyzed?

    metadata = screenshot.image.blob.metadata
    screenshot.update!(
      width: metadata["width"],
      height: metadata["height"],
      status: :ready
    )
  end
end
