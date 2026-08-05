# frozen_string_literal: true

module ScreenshotImages
  class EnsureProcessing
    INLINE_KEY = :screenote_inline_screenshot_processing

    class << self
      def call(image:)
        new(image:).call
      end

      def inline
        previous = ActiveSupport::IsolatedExecutionState[INLINE_KEY]
        ActiveSupport::IsolatedExecutionState[INLINE_KEY] = true
        yield
      ensure
        ActiveSupport::IsolatedExecutionState[INLINE_KEY] = previous
      end

      def inline?
        ActiveSupport::IsolatedExecutionState[INLINE_KEY]
      end
    end

    def initialize(image:)
      @image = image
    end

    def call
      image.reload
      return :skipped unless image.image.attached?

      if image.status_pending?
        dispatch(ScreenshotDimensionJob, image, image.image.blob.id, stage: "dimensions")
      elsif thumbnail_needed?
        dispatch(ScreenshotThumbnailJob, image, image.image.blob.id, stage: "thumbnails")
      else
        :skipped
      end
    end

    private

    attr_reader :image

    def thumbnail_needed?
      image.status_ready? &&
        image.thumbnail_warmable?(blob_id: image.image.blob.id) &&
        !image.thumbnail_variants_warmed?
    end

    def dispatch(job_class, *arguments, stage:)
      if self.class.inline?
        job_class.perform_now(*arguments)
        :processed
      else
        job = job_class.perform_later(*arguments)
        raise ActiveJob::EnqueueError, "#{stage} job was not enqueued" unless job.successfully_enqueued?

        :enqueued
      end
    rescue ActiveJob::EnqueueError, ActiveRecord::ActiveRecordError => error
      Screenote::Monitoring.notify(
        "Screenshot processing deferred",
        context: { screenshot_image_id: image.id, stage: stage, error_class: error.class.name }
      )
      :deferred
    end
  end
end
