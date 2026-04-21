# frozen_string_literal: true

# Reverse of ScreenshotImageBackfillService. Moves each ScreenshotImage(:desktop)
# blob back onto its parent Screenshot and destroys the ScreenshotImage. Used
# before rolling back the multi-viewport feature in production — otherwise
# `rails db:rollback` drops the screenshot_images table and orphans the blobs.
#
# Idempotent: re-running skips ScreenshotImages whose parent already has the
# image back. Leaves ScreenshotImages without an attached image alone.
class ScreenshotImageRollbackService
  Result = Struct.new(:already_rolled_back, :rolled_back, :no_image, :errors, keyword_init: true)

  def self.apply!(logger: $stdout)
    new(apply: true, logger: logger).call
  end

  def initialize(apply: false, logger: $stdout)
    @apply = apply
    @logger = logger
    @stats = { already_rolled_back: 0, rolled_back: 0, no_image: 0, errors: 0 }
  end

  def call
    ScreenshotImage.where(viewport: :desktop).find_each { |si| process(si) }
    Result.new(**@stats)
  end

  private

  def process(screenshot_image)
    screenshot = screenshot_image.screenshot

    if screenshot.image.attached?
      @stats[:already_rolled_back] += 1
      return
    end

    unless screenshot_image.image.attached?
      @stats[:no_image] += 1
      return
    end

    log "- ScreenshotImage##{screenshot_image.id} (Screenshot##{screenshot.id}): restoring blob"
    return unless @apply

    begin
      Screenshot.transaction do
        blob = screenshot_image.image.blob
        screenshot_image.image.detach
        screenshot.image.attach(blob)
        screenshot_image.destroy!
      end
      @stats[:rolled_back] += 1
    rescue StandardError => e
      log "x Screenshot##{screenshot.id}: #{e.class}: #{e.message}"
      @stats[:errors] += 1
    end
  end

  def log(message)
    @logger.puts(message)
  end
end
