# frozen_string_literal: true

class ReconcileScreenshotProcessingJob < ApplicationJob
  queue_as :default

  limits_concurrency key: -> { "screenshot-processing-reconciliation" },
    duration: 30.minutes,
    on_conflict: :discard

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
