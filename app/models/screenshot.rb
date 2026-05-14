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

  generates_token_for :upload, expires_in: 5.minutes do
    image.attached?.to_s
  end

  validates :title, presence: true, length: { maximum: 255 }
  validates :width, :height, numericality: { only_integer: true, greater_than: 0 }, allow_nil: true
  validate :acceptable_image
  validate :snapshot_belongs_to_same_project, if: :snapshot_id?

  # Returns the ScreenshotImage to render when no specific viewport is requested.
  # Prefers :desktop, falls back to the next viewport by the underlying enum
  # integer (desktop=0 < tablet=1 < mobile=2) so the loaded and cold paths
  # agree — `min_by(&:viewport)` on the enum string would compare
  # alphabetically and silently swap the result for the unloaded case.
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

  def acceptable_image
    return unless image.attached?

    unless image.blob.content_type.in?(ALLOWED_CONTENT_TYPES)
      errors.add(:image, "must be a PNG or JPEG")
    end

    if image.blob.byte_size > MAX_FILE_SIZE
      errors.add(:image, "is too large (max #{MAX_FILE_SIZE / 1.megabyte}MB)")
    end
  end

  def snapshot_belongs_to_same_project
    return if snapshot.nil?
    return if page && snapshot.project_id == page.project_id

    errors.add(:snapshot, "must belong to the same project as the page")
  end
end
