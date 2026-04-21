# frozen_string_literal: true

# One rendered image variant of a Screenshot, scoped to a viewport (desktop /
# tablet / mobile). A Screenshot can have 1..3 of these — single-viewport
# captures still work by having a single ScreenshotImage with viewport: :desktop.
# See plans/multi-viewport-screenshots.md.
class ScreenshotImage < ApplicationRecord
  # ScreenshotImage owns the blob post-PR-2. Screenshot references these
  # constants via the reverse direction during the transition (see PR-1's
  # original direction). Can be simplified further once Screenshot's legacy
  # has_one_attached :image is dropped (todo 172).
  ALLOWED_CONTENT_TYPES = %w[image/png image/jpeg].freeze
  MAX_FILE_SIZE = 20.megabytes

  BackfillResult = Struct.new(:already_backfilled, :backfilled, :no_image, :errors, keyword_init: true)
  RollbackResult = Struct.new(:already_rolled_back, :rolled_back, :no_image, :errors, keyword_init: true)

  belongs_to :screenshot
  has_one_attached :image

  enum :viewport, { desktop: 0, tablet: 1, mobile: 2 }, prefix: :viewport
  enum :status, { pending: 0, ready: 1, failed: 2 }, default: :pending, prefix: :status

  generates_token_for :upload, expires_in: 5.minutes do
    image.attached?.to_s
  end

  validates :viewport, uniqueness: { scope: :screenshot_id }
  validates :width, :height, numericality: { only_integer: true, greater_than: 0 }, allow_nil: true
  validate :acceptable_image

  after_create_commit :extract_dimensions_later

  # Move every attached Screenshot#image blob onto a new ScreenshotImage(:desktop).
  # Idempotent. Screenshots without an attached image are left alone.
  # Logger receives one line per record (prefix `+` migrated, `x` error). Pass
  # a logger that prints via `say` when running from a migration, or $stdout
  # for the Rake task. Completes even if individual records error — caller
  # decides how to react to `result.errors`.
  def self.backfill_from_screenshots!(apply: false, logger: $stdout)
    stats = { already_backfilled: 0, backfilled: 0, no_image: 0, errors: 0 }

    Screenshot.find_each do |screenshot|
      existing = screenshot.screenshot_images.find_by(viewport: :desktop)

      if existing&.image&.attached?
        stats[:already_backfilled] += 1
        next
      end

      unless screenshot.image.attached?
        stats[:no_image] += 1
        next
      end

      logger.puts "+ Screenshot##{screenshot.id} (#{screenshot.title.truncate(40)}): migrating blob #{screenshot.image.blob.id}"
      next unless apply

      begin
        move_blob_from_screenshot!(screenshot, existing)
        stats[:backfilled] += 1
      rescue StandardError => e
        logger.puts "x Screenshot##{screenshot.id}: #{e.class}: #{e.message}"
        stats[:errors] += 1
      end
    end

    BackfillResult.new(**stats)
  end

  # Inverse of backfill_from_screenshots! — moves ScreenshotImage(:desktop)
  # blobs back onto Screenshot and destroys the ScreenshotImage. Use before
  # rolling back the multi-viewport feature to avoid orphaning blobs (AS
  # attachments are polymorphic, no FK cascade).
  def self.rollback_to_screenshots!(apply: false, logger: $stdout)
    stats = { already_rolled_back: 0, rolled_back: 0, no_image: 0, errors: 0 }

    where(viewport: :desktop).find_each do |screenshot_image|
      screenshot = screenshot_image.screenshot

      if screenshot.image.attached?
        stats[:already_rolled_back] += 1
        next
      end

      unless screenshot_image.image.attached?
        stats[:no_image] += 1
        next
      end

      logger.puts "- ScreenshotImage##{screenshot_image.id} (Screenshot##{screenshot.id}): restoring blob"
      next unless apply

      begin
        move_blob_to_screenshot!(screenshot, screenshot_image)
        stats[:rolled_back] += 1
      rescue StandardError => e
        logger.puts "x Screenshot##{screenshot.id}: #{e.class}: #{e.message}"
        stats[:errors] += 1
      end
    end

    RollbackResult.new(**stats)
  end

  def self.move_blob_from_screenshot!(screenshot, existing)
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
  private_class_method :move_blob_from_screenshot!

  def self.move_blob_to_screenshot!(screenshot, screenshot_image)
    Screenshot.transaction do
      blob = screenshot_image.image.blob
      screenshot_image.image.detach
      screenshot.image.attach(blob)
      screenshot_image.destroy!
    end
  end
  private_class_method :move_blob_to_screenshot!

  private

  def extract_dimensions_later
    ScreenshotDimensionJob.perform_later(self)
  end

  def acceptable_image
    return unless image.attached?

    unless image.blob.content_type.in?(ALLOWED_CONTENT_TYPES)
      errors.add(:image, "must be a PNG or JPEG")
    end

    if image.blob.byte_size > MAX_FILE_SIZE
      errors.add(:image, "is too large (max #{MAX_FILE_SIZE / 1.megabyte}MB)")
    end
  end
end
