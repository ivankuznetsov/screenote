# frozen_string_literal: true

class Screenshot < ApplicationRecord
  belongs_to :project
  has_many :annotations, dependent: :destroy
  ALLOWED_CONTENT_TYPES = %w[image/png image/jpeg].freeze
  MAX_FILE_SIZE = 20.megabytes

  has_one_attached :image

  enum :status, { pending: 0, ready: 1, failed: 2 }, default: :pending

  validates :title, presence: true, length: { maximum: 255 }
  validates :width, :height, numericality: { only_integer: true, greater_than: 0 }, allow_nil: true
  validate :acceptable_image

  after_create_commit :extract_dimensions_later

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
