# frozen_string_literal: true

class ScreenshotDimensionJob < ApplicationJob
  # Accepts either a ScreenshotImage (new callers) or a Screenshot (legacy
  # enqueued jobs in flight when PR-2 deploys). The Screenshot path attempts to
  # forward to the primary ScreenshotImage; if none exists yet (backfill
  # pending), it exits quietly and relies on ScreenshotImage's own
  # after_create_commit callback to enqueue a fresh job.
  def perform(record)
    screenshot_image = resolve_target(record)
    return unless screenshot_image

    return if screenshot_image.status_ready?

    unless screenshot_image.image.attached?
      Rails.logger.warn("ScreenshotDimensionJob: ScreenshotImage #{screenshot_image.id} has no attached image")
      return
    end

    screenshot_image.image.blob.analyze unless screenshot_image.image.blob.analyzed?

    metadata = screenshot_image.image.blob.metadata
    width = metadata["width"]
    height = metadata["height"]

    if width.present? && height.present?
      screenshot_image.update!(width: width, height: height, status: :ready)
    else
      Honeybadger.notify("ScreenshotImage dimension extraction failed",
        context: { screenshot_image_id: screenshot_image.id, metadata: metadata })
      screenshot_image.update!(status: :failed)
    end
  end

  private

  def resolve_target(record)
    case record
    when ScreenshotImage
      record
    when Screenshot
      record.primary_image
    end
  end
end
