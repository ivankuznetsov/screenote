# frozen_string_literal: true

# One rendered image variant of a Screenshot, scoped to a viewport (desktop /
# tablet / mobile). A Screenshot can have 1..3 of these — single-viewport
# captures still work by having a single ScreenshotImage with viewport: :desktop.
# See plans/multi-viewport-screenshots.md.
class ScreenshotImage < ApplicationRecord
  ALLOWED_CONTENT_TYPES = Screenshot::ALLOWED_CONTENT_TYPES
  MAX_FILE_SIZE = Screenshot::MAX_FILE_SIZE

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

  # Crop the region of this image that corresponds to the given annotation.
  # Returns a Base64-encoded PNG string suitable for MCP responses. Cached.
  def crop_for(annotation)
    AnnotationCropService.crop(self, annotation)
  end

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
