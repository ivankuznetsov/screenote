# frozen_string_literal: true

class Screenshot < ApplicationRecord
  # Dimensions live on ScreenshotImage. These columns are dropped by a
  # follow-up migration once no running release still inserts them.
  self.ignored_columns += %w[width height]

  belongs_to :page
  belongs_to :snapshot, optional: true
  has_one :project, through: :page
  has_many :annotations, dependent: :destroy
  has_many :screenshot_images, dependent: :destroy

  enum :status, { pending: 0, ready: 1, failed: 2 }, default: :pending

  scope :recent_first, -> { order(created_at: :desc, id: :desc) }
  # The newest ready version of each page, by the same created_at-then-id
  # order as recent_first. A correlated NOT EXISTS keeps the lookup bounded by
  # the pages being loaded instead of aggregating every screenshot.
  scope :latest_ready_per_page, -> {
    newer = arel_table.alias("newer_screenshots")
    newer_ready_version = arel_table
      .project(Arel.sql("1"))
      .from(newer)
      .where(newer[:page_id].eq(arel_table[:page_id]))
      .where(newer[:status].eq(statuses[:ready]))
      .where(
        newer[:created_at].gt(arel_table[:created_at]).or(
          newer[:created_at].eq(arel_table[:created_at]).and(newer[:id].gt(arel_table[:id]))
        )
      )

    ready.where(Arel::Nodes::Not.new(newer_ready_version.exists))
  }

  before_validation :normalize_manifest_entry_digest
  before_validation :lock_snapshot_for_page_identity, if: :snapshot_page_identity_changed?

  validates :title, presence: true, length: { maximum: 255 }
  validates :manifest_entry_digest,
    format: { with: Snapshot::SHA256_FORMAT, message: Snapshot::SHA256_ERROR_MESSAGE },
    uniqueness: { scope: :snapshot_id },
    allow_nil: true
  validates :page_id,
    uniqueness: { scope: :snapshot_id, message: "can only have one version per snapshot" },
    if: :snapshot_page_identity_changed?
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

  # Defense-in-depth at the AR layer only; raw SQL updates bypass it.
  def snapshot_belongs_to_same_project
    return if snapshot.nil?
    return if page && snapshot.project_id == page.project_id

    errors.add(:snapshot, "must belong to the same project as the page")
  end

  def lock_snapshot_for_page_identity
    snapshot&.lock!
  end

  def snapshot_page_identity_changed?
    snapshot_id? && (new_record? || will_save_change_to_snapshot_id? || will_save_change_to_page_id?)
  end
end
