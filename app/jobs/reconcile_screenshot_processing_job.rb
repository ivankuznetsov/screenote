# frozen_string_literal: true

class ReconcileScreenshotProcessingJob < ApplicationJob
  queue_as :default

  limits_concurrency key: -> { "screenshot-processing-reconciliation" },
    duration: 30.minutes,
    on_conflict: :discard

  def self.enqueue_for_startup!
    job = nil
    perform_later { |candidate| job = candidate }
    raise job.enqueue_error if job.enqueue_error

    job
  end

  def perform
    processed = 0

    ScreenshotImages::EnsureProcessing.inline do
      ScreenshotImage.joins(:image_attachment).find_each do |image|
        result = ScreenshotImages::EnsureProcessing.call(image:)
        processed += 1 if result == :processed
      rescue StandardError => error
        Screenote::Monitoring.notify(
          "Screenshot processing reconciliation failed",
          context: { screenshot_image_id: image.id, error_class: error.class.name }
        )
      end
    end

    processed
  end
end
