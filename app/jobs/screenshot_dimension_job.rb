# frozen_string_literal: true

class ScreenshotDimensionJob < ApplicationJob
  self.enqueue_after_transaction_commit = !Rails.env.test?

  retry_on ImageDecoding::Guard::Busy, wait: 5.seconds, attempts: 10

  limits_concurrency key: ->(record, blob_id = nil) {
    blob_id ? "#{record.to_global_id}/blob/#{blob_id}" : record
  }, duration: 3.minutes, on_conflict: :discard

  # Accepts either a ScreenshotImage (new callers) or a Screenshot (legacy
  # enqueued jobs in flight when PR-2 deploys). The Screenshot path attempts to
  # forward to the primary ScreenshotImage; if none exists yet (backfill
  # pending), it exits quietly and relies on ScreenshotImage's own
  # after_create_commit callback to enqueue a fresh job.
  def perform(record, blob_id = nil)
    screenshot_image = resolve_target(record)
    if screenshot_image.nil?
      # Legacy Screenshot-arg whose primary_image isn't ready yet (possible
      # briefly during the PR-2 deploy window before the backfill migration
      # completes). Raise so Solid Queue retries rather than silently drop
      # dimension extraction and leave the Screenshot pending forever.
      raise "ScreenshotDimensionJob: no primary_image for #{record.class}##{record.id}"
    end

    if screenshot_image.status_ready?
      ScreenshotImages::EnsureProcessing.call(image: screenshot_image)
      return
    end

    current_blob_id = attached_blob_id(screenshot_image)
    unless current_blob_id
      Rails.logger.warn("ScreenshotDimensionJob: ScreenshotImage #{screenshot_image.id} has no attached image")
      return
    end

    # One-argument jobs may still be in flight during deployment. Treat the
    # blob attached when they start as their generation so they get the same
    # stale-completion protection as newly enqueued two-argument jobs.
    blob_id ||= current_blob_id
    return unless blob_id.to_s == current_blob_id.to_s

    blob = screenshot_image.image.blob
    metadata = analyze_blob(blob)

    width = metadata["width"]
    height = metadata["height"]

    # Analysis can be slow. Serialize the final generation check with the
    # replacement paths and never apply dimensions produced for a detached
    # blob to the ScreenshotImage's newer attachment.
    dimensions_applied = false
    screenshot_image.with_lock do
      return unless blob_id.to_s == attached_blob_id(screenshot_image).to_s

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

  def resolve_target(record)
    case record
    when ScreenshotImage
      record
    when Screenshot
      record.primary_image
    else
      raise ArgumentError, "ScreenshotDimensionJob cannot handle #{record.class}"
    end
  end
end
