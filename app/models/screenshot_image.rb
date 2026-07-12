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

  before_validation :normalize_content_sha256

  generates_token_for :upload, expires_in: 5.minutes do
    image.attached?.to_s
  end

  validates :viewport, uniqueness: { scope: :screenshot_id }
  validates :width, :height, numericality: { only_integer: true, greater_than: 0 }, allow_nil: true
  validates :content_sha256,
    format: { with: Snapshot::SHA256_FORMAT, message: Snapshot::SHA256_ERROR_MESSAGE },
    allow_nil: true
  validates :expected_content_type, inclusion: { in: ALLOWED_CONTENT_TYPES }, allow_nil: true
  validate :acceptable_image
  validate :manifest_content_identity

  after_create_commit :ensure_dimension_processing
  # Keep Screenshot#status in sync with children so queries like
  # `Page.screenshots.where(status: :ready)` and readers like
  # `Screenshot#status` reflect the actual analysis state of the image
  # variants. Without this, Screenshot#status is stuck at :pending forever
  # after PR-2.
  after_save :sync_parent_status, if: :saved_change_to_status?
  after_destroy :sync_parent_status

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

  # Rolls a variant back onto the parent Screenshot for pre-rollback data
  # restoration. Critical detail: Screenshot's status/width/height columns
  # must be set AFTER destroy! so the after_destroy :sync_parent_status
  # callback (which recomputes status from surviving children = :pending when
  # the last variant disappears) doesn't wipe the restored values. The legacy
  # code path this rollback enables — readers that predate PR-2 — reads
  # width/height/status off Screenshot directly.
  def self.move_blob_to_screenshot!(screenshot, screenshot_image)
    Screenshot.transaction do
      blob = screenshot_image.image.blob
      width = screenshot_image.width
      height = screenshot_image.height
      status_key = screenshot_image.status

      screenshot_image.image.detach
      screenshot.image.attach(blob)
      screenshot_image.destroy! # fires sync_parent_status → parent becomes :pending

      screenshot.update_columns(
        width: width,
        height: height,
        status: Screenshot.statuses[status_key]
      )
    end
  end
  private_class_method :move_blob_to_screenshot!

  # Only enqueue dimension extraction when there's something to analyze AND
  # the record isn't already :ready:
  #   - The signed-upload flow creates a blank ScreenshotImage first and the
  #     agent PUTs the blob later. Without this guard, the create-time
  #     callback enqueues a useless job that only logs a warning and exits,
  #     and the upload controller enqueues a second (real) job after attach.
  #   - The backfill Rake task copies width/height/status=:ready from the
  #     parent; those records don't need re-analysis.
  def ensure_dimension_processing
    return unless image.attached?
    return if status_ready?

    ScreenshotDimensionJob.perform_later(self, image.blob.id)
  end

  private

  def normalize_content_sha256
    self.content_sha256 = content_sha256.to_s.strip.downcase.presence
    self.expected_content_type = expected_content_type.to_s.strip.downcase.presence
  end

  def manifest_content_identity
    return unless screenshot&.snapshot&.manifest_backed?

    errors.add(:content_sha256, :blank) if content_sha256.blank?
    errors.add(:expected_content_type, :blank) if expected_content_type.blank?
  end

  # :ready iff every sibling variant is :ready; :failed if any is :failed;
  # :pending otherwise (including the no-variants case). update_columns skips
  # Screenshot callbacks/validations — this is a derived field, not user input.
  def sync_parent_status
    # Skip when the parent is mid-destroy — dependent: :destroy on
    # screenshot_images triggers this callback but the Screenshot itself
    # is already destroyed and cannot be updated.
    return if screenshot.destroyed? || screenshot.marked_for_destruction?

    # Re-fetch parent + siblings from the DB so we don't rely on cached
    # associations that may be stale (callers often manipulate the parent's
    # status via update_columns before triggering this callback in tests).
    parent = Screenshot.find_by(id: screenshot_id)
    return unless parent

    siblings = parent.screenshot_images
    desired = if siblings.where(status: :failed).exists?
      :failed
    elsif siblings.exists? && !siblings.where.not(status: :ready).exists?
      :ready
    else
      :pending
    end
    return if parent.status == desired.to_s

    parent.update_columns(status: Screenshot.statuses[desired])
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
