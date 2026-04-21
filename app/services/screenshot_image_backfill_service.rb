# frozen_string_literal: true

# Moves Active Storage blobs from Screenshot to a new ScreenshotImage(:desktop)
# for every Screenshot that has an attached image. Used by both the deploy-time
# backfill migration and the operator-facing rake task — one source of truth.
#
# Idempotent: re-running skips Screenshots whose desktop variant already has
# its blob attached. Screenshots without an attached image are left alone
# (readers treat screenshot_images.empty? as "no image yet").
#
# Usage:
#   ScreenshotImageBackfillService.new.call                  # dry run
#   ScreenshotImageBackfillService.new(apply: true).call     # commit
#   ScreenshotImageBackfillService.apply!                    # convenience
class ScreenshotImageBackfillService
  Result = Struct.new(:already_backfilled, :backfilled, :no_image, :errors, keyword_init: true)

  def self.apply!(logger: $stdout)
    new(apply: true, logger: logger).call
  end

  def initialize(apply: false, logger: $stdout)
    @apply = apply
    @logger = logger
    @stats = { already_backfilled: 0, backfilled: 0, no_image: 0, errors: 0 }
  end

  def call
    Screenshot.find_each { |screenshot| process(screenshot) }
    Result.new(**@stats)
  end

  private

  def process(screenshot)
    existing = screenshot.screenshot_images.find_by(viewport: :desktop)

    if existing&.image&.attached?
      @stats[:already_backfilled] += 1
      return
    end

    unless screenshot.image.attached?
      @stats[:no_image] += 1
      return
    end

    log "+ Screenshot##{screenshot.id} (#{screenshot.title.truncate(40)}): migrating blob #{screenshot.image.blob.id}"
    return unless @apply

    begin
      move_blob!(screenshot, existing)
      @stats[:backfilled] += 1
    rescue StandardError => e
      log "x Screenshot##{screenshot.id}: #{e.class}: #{e.message}"
      @stats[:errors] += 1
    end
  end

  def move_blob!(screenshot, existing)
    Screenshot.transaction do
      blob = screenshot.image.blob
      screenshot.image.detach
      target = existing || screenshot.screenshot_images.create!(
        viewport: :desktop,
        status: screenshot.status,
        width: screenshot.width,
        height: screenshot.height
      )
      target.image.attach(blob)
    end
  end

  def log(message)
    @logger.puts(message)
  end
end
