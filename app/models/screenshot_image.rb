# frozen_string_literal: true

# One rendered image of a Screenshot, scoped to a viewport (desktop / tablet /
# mobile). A Screenshot can have 1..3 of these — single-viewport captures have
# a single ScreenshotImage with viewport: :desktop. It owns the uploaded blob.
class ScreenshotImage < ApplicationRecord
  ALLOWED_CONTENT_TYPES = %w[image/png image/jpeg].freeze
  MAX_FILE_SIZE = 20.megabytes
  MAX_DIMENSION = 32_768
  MAX_PIXELS = 50_000_000
  THUMBNAIL_VARIANT_NAMES = %i[page_card_1x page_card_2x project_strip].freeze
  OVERVIEW_IMAGE_PRELOAD = {
    image_attachment: {
      blob: {
        variant_records: { image_attachment: :blob },
        preview_image_attachment: {
          blob: { variant_records: { image_attachment: :blob } }
        }
      }
    }
  }.freeze

  ThumbnailWarmResult = Struct.new(:candidates, :skipped, :processed, :failed, keyword_init: true)

  belongs_to :screenshot
  has_one_attached :image do |attachable|
    attachable.variant :page_card_1x, resize_to_fill: [ 480, 270 ]
    attachable.variant :page_card_2x, resize_to_fill: [ 960, 540 ]
    attachable.variant :project_strip, resize_to_fill: [ 240, 160 ]
  end

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
  # Screenshot#status is derived from its images so queries like
  # `Page.screenshots.where(status: :ready)` reflect their analysis state.
  after_save :sync_parent_status, if: :saved_change_to_status?
  after_destroy :sync_parent_status

  # The images ScreenshotImages::EnsureProcessing would act on: attached and
  # still awaiting dimensions, or the ready primary image of a ready Screenshot
  # whose blob lacks a thumbnail variant. EnsureProcessing stays the
  # authoritative per-row check; this keeps reconciliation off finished work.
  def self.needing_processing
    attached = joins(:image_attachment)

    attached.status_pending.or(
      attached.status_ready
        .where(screenshot_id: Screenshot.ready.select(:id))
        .where(primary_viewport)
        .where(missing_thumbnail_variant)
    )
  end

  # Active Storage folds the blob's format into every variant digest, and the
  # format follows the upload's filename extension, which clients choose. List
  # each named thumbnail's digest for every spelling an allowed content type
  # can resolve to; a blob named some other way only costs EnsureProcessing one
  # redundant check per reconciliation pass.
  def self.thumbnail_variant_digests
    blobs = ALLOWED_CONTENT_TYPES.flat_map do |content_type|
      Marcel::Magic.new(content_type).extensions
        .flat_map { |extension| [ extension, extension.upcase ] }
        .map { |extension| ActiveStorage::Blob.new(filename: "image.#{extension}", content_type:) }
    end
    named_variants = attachment_reflections.fetch("image").named_variants

    THUMBNAIL_VARIANT_NAMES.index_with do |name|
      transformations = named_variants.fetch(name).transformations
      blobs.map { |blob| blob.variant(transformations).variation.digest }.uniq
    end
  end

  # Desktop when present, else the lowest viewport: Screenshot#primary_image.
  def self.primary_viewport
    siblings = arel_table.alias("sibling_images")
    lower_sibling = arel_table
      .project(Arel.sql("1"))
      .from(siblings)
      .where(siblings[:screenshot_id].eq(arel_table[:screenshot_id]))
      .where(siblings[:viewport].lt(arel_table[:viewport]))

    Arel::Nodes::Not.new(lower_sibling.exists)
  end
  private_class_method :primary_viewport

  def self.missing_thumbnail_variant
    variant_records = ActiveStorage::VariantRecord.arel_table
    same_blob = variant_records[:blob_id].eq(ActiveStorage::Attachment.arel_table[:blob_id])

    thumbnail_variant_digests.values
      .map { |digests| ActiveStorage::VariantRecord.where(same_blob).where(variation_digest: digests).arel.exists.not }
      .reduce(:or)
  end
  private_class_method :missing_thumbnail_variant

  # Warms the named overview variants for every current, ready primary image.
  # Dry-run is the default: eligible records are counted as candidates but no
  # image processing or Active Storage writes occur.
  def self.warm_thumbnails!(apply: false, batch_size: 1000, logger: $stdout)
    stats = { candidates: 0, skipped: 0, processed: 0, failed: 0 }

    find_each(batch_size: batch_size) do |screenshot_image|
      blob_id = screenshot_image.image_attachment&.blob_id

      unless blob_id &&
          screenshot_image.thumbnail_warmable?(blob_id:) &&
          !screenshot_image.thumbnail_variants_warmed?
        stats[:skipped] += 1
        next
      end

      stats[:candidates] += 1
      logger.puts "+ ScreenshotImage##{screenshot_image.id} blob=#{blob_id}"
      next unless apply

      result = ScreenshotThumbnailJob.perform_now(screenshot_image, blob_id)
      stats[result == :processed ? :processed : :skipped] += 1
    rescue StandardError => e
      logger.puts "x ScreenshotImage##{screenshot_image.id}: #{e.class}: #{e.message}"
      stats[:failed] += 1
    end

    ThumbnailWarmResult.new(**stats)
  end

  # Only enqueue dimension extraction when there's something to analyze and
  # the record isn't already :ready. The signed-upload flow creates a blank
  # ScreenshotImage first and the agent PUTs the blob later; the upload path
  # schedules processing once the blob is attached.
  def ensure_dimension_processing
    return unless image.attached?
    return if status_ready?

    ScreenshotImages::EnsureProcessing.call(image: self)
  end

  def thumbnail_variants
    return [] unless image.attached?

    THUMBNAIL_VARIANT_NAMES.map { |name| image.variant(name) }
  end

  def thumbnail_variants_warmed?
    variants = thumbnail_variants
    return false unless variants.size == THUMBNAIL_VARIANT_NAMES.size

    digests = variants.map { |variant| variant.variation.digest }
    image.blob.variant_records.where(variation_digest: digests).distinct.count == digests.size
  end

  # Overview rendering must only use the bulk-preloaded variant records. A
  # representation URL for an unprocessed variant causes Active Storage to
  # process it synchronously when the browser fetches it, so a request must
  # treat an unloaded association as not warmed rather than querying for it.
  def overview_variants_warmed?
    return false unless image.attached?

    variant_records = image.blob.association(:variant_records)
    return false unless variant_records.loaded?

    digests = thumbnail_variants.map { |variant| variant.variation.digest }
    digests.size == THUMBNAIL_VARIANT_NAMES.size &&
      digests.all? { |digest| variant_records.target.any? { |record| record.variation_digest == digest } }
  end

  # Re-resolves the parent and its image association on every call so queued
  # jobs cannot warm a replaced blob or a viewport that is no longer primary.
  def thumbnail_warmable?(blob_id:)
    return false unless persisted? && status_ready? && image.attached?
    return false unless image_attachment.blob_id.to_s == blob_id.to_s

    parent = Screenshot.includes(:screenshot_images).find_by(id: screenshot_id)
    parent&.ready? && parent.primary_image&.id == id
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
