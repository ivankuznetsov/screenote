# frozen_string_literal: true

class Screenshot < ApplicationRecord
  # Canonical constants now live on ScreenshotImage (the real owner of the blob).
  # Screenshot re-exposes them for the still-present has_one_attached :image
  # (backfill code path, to be removed in PR-3 alongside todo 172).
  ALLOWED_CONTENT_TYPES = ScreenshotImage::ALLOWED_CONTENT_TYPES
  MAX_FILE_SIZE = ScreenshotImage::MAX_FILE_SIZE

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

  # Returns the ScreenshotImage to render when no specific viewport is requested.
  # Prefers :desktop, falls back to the first available viewport, nil if none.
  def primary_image
    screenshot_images.find_by(viewport: :desktop) || screenshot_images.order(:viewport).first
  end

  # Returns the ScreenshotImage matching the given viewport (enum symbol or string), or nil.
  def image_for(viewport)
    screenshot_images.find_by(viewport: viewport)
  end

  # Array of viewport names (as strings, matching the enum) that have a ScreenshotImage.
  def available_viewports
    screenshot_images.order(:viewport).pluck(:viewport)
  end

  # The viewport to activate on page load — desktop if present, else the first available.
  def default_viewport
    vps = available_viewports
    vps.include?("desktop") ? "desktop" : vps.first
  end

  # Canonical factory for "new Screenshot with an image attached". Creates the
  # Screenshot + a ScreenshotImage(:desktop) + attaches + saves everything in
  # one transaction so validators run and partial state can't persist.
  #
  # Callers: web form, MCP create_screenshot, API v1, signed-upload flow.
  # Returns the saved Screenshot (with its ScreenshotImage accessible via
  # `screenshot.primary_image`).
  def self.create_with_image!(page:, title:, io:, filename:, content_type:, viewport: :desktop)
    screenshot = nil
    transaction do
      screenshot = page.screenshots.create!(title: title)
      si = screenshot.screenshot_images.create!(viewport: viewport)
      si.image.attach(io: io, filename: filename, content_type: content_type)
      si.save!
    end
    screenshot
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
