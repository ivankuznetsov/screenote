# frozen_string_literal: true

class Snapshot < ApplicationRecord
  GIT_COMMIT_FORMAT = /\A[0-9a-f]{7,40}\z/
  SHA256_FORMAT = /\A[0-9a-f]{64}\z/
  SHA256_ERROR_MESSAGE = "must be a 64-character hexadecimal SHA-256"
  FUTURE_SKEW = 5.minutes

  belongs_to :project
  has_many :screenshots, dependent: :nullify
  has_many :screenshot_images, through: :screenshots

  before_validation :default_taken_at
  before_validation :normalize_git_commit
  before_validation :normalize_manifest_digest

  validates :git_commit, presence: true,
    format: { with: GIT_COMMIT_FORMAT, allow_blank: true,
              message: "must be 7-40 hexadecimal characters" }
  validates :taken_at, presence: true
  validates :manifest_digest,
    format: { with: SHA256_FORMAT, message: SHA256_ERROR_MESSAGE },
    uniqueness: { scope: :project_id },
    allow_nil: true
  validate :taken_at_not_in_future

  # Unbounded by design — callers must `.limit(...)` before rendering. Tie-break
  # by id so two snapshots created in the same second (CLI retry) sort stably
  # across supported databases.
  scope :recent, -> { order(taken_at: :desc, id: :desc) }

  def short_commit
    git_commit.to_s.first(7)
  end

  def label
    @label ||= "#{taken_at.utc.to_date.iso8601} · #{short_commit}"
  end

  def thumbnails_for(pages)
    page_ids = pages.map(&:id)
    return {} if page_ids.empty?

    screenshots_table = Screenshot.arel_table
    newer_screenshots = screenshots_table.alias("newer_screenshots")
    newer_version = newer_screenshots[:created_at].gt(screenshots_table[:created_at]).or(
      newer_screenshots[:created_at].eq(screenshots_table[:created_at]).and(
        newer_screenshots[:id].gt(screenshots_table[:id])
      )
    )
    newer_ready_screenshot = screenshots_table
      .project(Arel.sql("1"))
      .from(newer_screenshots)
      .where(newer_screenshots[:snapshot_id].eq(screenshots_table[:snapshot_id]))
      .where(newer_screenshots[:page_id].eq(screenshots_table[:page_id]))
      .where(newer_screenshots[:status].eq(Screenshot.statuses[:ready]))
      .where(newer_version)

    candidates = screenshots
      .ready
      .where(page_id: page_ids)
      .where(Arel::Nodes::Not.new(newer_ready_screenshot.exists))
      .order(created_at: :desc, id: :desc)
      .includes(screenshot_images: ScreenshotImage::OVERVIEW_IMAGE_PRELOAD)

    candidates.index_by(&:page_id)
  end

  def manifest_backed?
    manifest_digest.present?
  end

  def aggregate_state
    images = screenshot_images
    return "awaiting_upload" unless images.exists?
    return "awaiting_upload" if images.where.missing(:image_attachment).exists?
    return "failed" if images.status_failed.exists?
    return "processing" if images.where.not(status: :ready).exists?

    "ready"
  end

  private

  def default_taken_at
    self.taken_at ||= Time.current
  end

  def normalize_git_commit
    return if git_commit.nil?

    self.git_commit = git_commit.strip.downcase
  end

  def normalize_manifest_digest
    self.manifest_digest = manifest_digest.to_s.strip.downcase.presence
  end

  def taken_at_not_in_future
    return if taken_at.blank? || taken_at <= Time.current + FUTURE_SKEW

    errors.add(:taken_at, "can't be in the future")
  end
end
