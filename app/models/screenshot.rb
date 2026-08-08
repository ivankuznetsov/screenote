# frozen_string_literal: true

class Screenshot < ApplicationRecord
  # Canonical constants live on ScreenshotImage (the real owner of the blob).
  # Screenshot re-exposes them for the still-present has_one_attached :image
  # used by the legacy upload path.
  ALLOWED_CONTENT_TYPES = ScreenshotImage::ALLOWED_CONTENT_TYPES
  MAX_FILE_SIZE = ScreenshotImage::MAX_FILE_SIZE

  belongs_to :page
  belongs_to :snapshot, optional: true
  has_one :project, through: :page
  has_many :annotations, dependent: :destroy
  has_many :screenshot_images, dependent: :destroy
  has_one_attached :image

  enum :status, { pending: 0, ready: 1, failed: 2 }, default: :pending

  scope :recent_first, -> { order(created_at: :desc, id: :desc) }

  before_validation :normalize_manifest_entry_digest

  generates_token_for :upload, expires_in: 5.minutes do
    image.attached?.to_s
  end

  validates :title, presence: true, length: { maximum: 255 }
  validates :width, :height, numericality: { only_integer: true, greater_than: 0 }, allow_nil: true
  validates :manifest_entry_digest,
    format: { with: Snapshot::SHA256_FORMAT, message: Snapshot::SHA256_ERROR_MESSAGE },
    uniqueness: { scope: :snapshot_id },
    allow_nil: true
  validate :acceptable_image
  validate :snapshot_belongs_to_same_project, if: :snapshot_id?
  validate :manifest_identity_matches_snapshot

  # Prefers :desktop, else lowest viewport enum int. Cold path's `order(:viewport)`
  # also sorts by the enum int (desktop=0 < tablet=1 < mobile=2), and the
  # unique `(screenshot_id, viewport)` index breaks ties — same shape, same
  # result on every supported database.
  def primary_image
    if screenshot_images.loaded?
      images = screenshot_images.to_a
      images.find { |si| si.viewport == "desktop" } ||
        images.min_by { |si| ScreenshotImage.viewports[si.viewport] }
    else
      screenshot_images.find_by(viewport: :desktop) || screenshot_images.order(:viewport).first
    end
  end

  # Returns the ScreenshotImage matching the given viewport (enum symbol or string), or nil.
  def image_for(viewport)
    if screenshot_images.loaded?
      screenshot_images.find { |image| image.viewport == viewport.to_s }
    else
      screenshot_images.find_by(viewport: viewport)
    end
  end

  # Array of viewport names (as strings, matching the enum) that have a ScreenshotImage.
  def available_viewports
    if screenshot_images.loaded?
      screenshot_images
        .sort_by { |image| ScreenshotImage.viewports.fetch(image.viewport) }
        .map(&:viewport)
    else
      screenshot_images.order(:viewport).pluck(:viewport)
    end
  end

  # The viewport to activate on page load — desktop if present, else the first available.
  def default_viewport
    vps = available_viewports
    vps.include?("desktop") ? "desktop" : vps.first
  end

  # Canonical factory: creates Screenshot + ScreenshotImage + attaches blob in one transaction.
  def self.create_with_image!(page:, title:, io:, filename:, content_type:, viewport: :desktop)
    screenshot = nil
    screenshot_image = nil
    transaction do
      screenshot = page.screenshots.create!(title: title)
      screenshot_image = screenshot.screenshot_images.create!(viewport: viewport)
      Snapshots::AttachImage.call(
        image: screenshot_image,
        io: io,
        filename: filename,
        declared_content_type: content_type,
        declared_length: (io.size if io.respond_to?(:size)),
        schedule_processing: false
      )
    end
    screenshot
  rescue Snapshots::AttachImage::Error => error
    screenshot_image.errors.add(:image, error.message)
    raise ActiveRecord::RecordInvalid, screenshot_image
  end

  def replace_primary_image!(io:, filename:, content_type:, declared_length: nil)
    screenshot_image = primary_image || screenshot_images.create!(viewport: :desktop)
    Snapshots::AttachImage.call(
      image: screenshot_image,
      io: io,
      filename: filename,
      declared_content_type: content_type,
      declared_length: declared_length || (io.size if io.respond_to?(:size)),
      replace_existing: true
    )
  rescue Snapshots::AttachImage::Error => error
    screenshot_image.errors.add(:image, error.message)
    raise ActiveRecord::RecordInvalid, screenshot_image
  end

  private

  def normalize_manifest_entry_digest
    self.manifest_entry_digest = manifest_entry_digest.to_s.strip.downcase.presence
  end

  def manifest_identity_matches_snapshot
    if snapshot&.manifest_backed?
      errors.add(:manifest_entry_digest, :blank) if manifest_entry_digest.blank?
    elsif manifest_entry_digest.present?
      errors.add(:manifest_entry_digest, "requires a manifest-backed snapshot")
    end
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

  # Defense-in-depth at the AR layer only; raw SQL updates bypass it.
  def snapshot_belongs_to_same_project
    return if snapshot.nil?
    return if page && snapshot.project_id == page.project_id

    errors.add(:snapshot, "must belong to the same project as the page")
  end
end
