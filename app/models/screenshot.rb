# frozen_string_literal: true

class Screenshot < ApplicationRecord
  ALLOWED_CONTENT_TYPES = %w[image/png image/jpeg].freeze
  MAX_FILE_SIZE = 20.megabytes

  belongs_to :page
  has_one :project, through: :page
  has_many :annotations, dependent: :destroy
  has_many :screenshot_images, dependent: :destroy
  has_one_attached :image

  enum :status, { pending: 0, ready: 1, failed: 2 }, default: :pending

  generates_token_for :upload, expires_in: 5.minutes do
    image.attached?.to_s
  end

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
