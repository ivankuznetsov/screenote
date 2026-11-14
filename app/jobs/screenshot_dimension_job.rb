# frozen_string_literal: true

class ScreenshotDimensionJob < ApplicationJob
  self.enqueue_after_transaction_commit = !Rails.env.test?

  retry_on ImageDecoding::Guard::Busy, wait: 5.seconds, attempts: 10
  # The screenshot can be deleted while its job is still queued.
  discard_on ActiveJob::DeserializationError

  limits_concurrency key: ->(screenshot_image, blob_id) {
    "#{screenshot_image.to_global_id}/blob/#{blob_id}"
  }, duration: 3.minutes, on_conflict: :discard

  # blob_id is the attachment generation this job was enqueued for. A job
  # whose blob has since been replaced leaves the newer attachment to the job
  # its replacement enqueued.
  def perform(screenshot_image, blob_id)
    if screenshot_image.status_ready?
      ScreenshotImages::EnsureProcessing.call(image: screenshot_image)
      return :skipped
    end

    current_blob_id = attached_blob_id(screenshot_image)
    unless current_blob_id
      Rails.logger.warn("ScreenshotDimensionJob: ScreenshotImage #{screenshot_image.id} has no attached image")
      return :skipped
    end
    return :skipped unless blob_id.to_s == current_blob_id.to_s

    blob = screenshot_image.image.blob
    metadata = analyze_blob(blob)

    width = metadata["width"]
    height = metadata["height"]

    # Analysis can be slow. Serialize the final generation check with the
    # replacement paths and never apply dimensions produced for a detached
    # blob to the ScreenshotImage's newer attachment.
    dimensions_applied = false
    screenshot_image.with_lock do
      return :skipped unless blob_id.to_s == attached_blob_id(screenshot_image).to_s

      if width.present? && height.present?
        screenshot_image.update!(width: width, height: height, status: :ready)
        dimensions_applied = true
      else
        Screenote::Monitoring.notify("ScreenshotImage dimension extraction failed",
          context: { screenshot_image_id: screenshot_image.id, metadata: metadata })
        screenshot_image.update!(status: :failed)
      end
    end

    enqueue_primary_thumbnail_warming(screenshot_image) if dimensions_applied
    :processed
  end

  private

  def analyze_blob(blob)
    ImageDecoding::Guard.synchronize { blob.analyze unless blob.analyzed? }
    blob.metadata
  end

  def attached_blob_id(screenshot_image)
    screenshot_image.image_attachment&.blob_id
  end

  # The final sibling to finish makes the logical Screenshot ready. Resolve
  # its primary image after the dimension transaction commits: desktop wins
  # even when a mobile/tablet sibling happened to finish last.
  def enqueue_primary_thumbnail_warming(screenshot_image)
    screenshot = Screenshot.includes(:screenshot_images).find_by(id: screenshot_image.screenshot_id)
    return unless screenshot&.ready?

    primary_image = screenshot.primary_image
    return unless primary_image&.image&.attached?

    ScreenshotImages::EnsureProcessing.call(image: primary_image)
  end
end
