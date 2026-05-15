# frozen_string_literal: true

class Snapshot < ApplicationRecord
  GIT_COMMIT_FORMAT = /\A[0-9a-f]{7,40}\z/
  FUTURE_SKEW = 5.minutes

  belongs_to :project
  has_many :screenshots, dependent: :nullify

  before_validation :default_taken_at
  before_validation :normalize_git_commit

  validates :git_commit, presence: true,
    format: { with: GIT_COMMIT_FORMAT, allow_blank: true,
              message: "must be 7-40 hexadecimal characters" }
  validates :taken_at, presence: true
  validate :taken_at_not_in_future

  # Unbounded by design — callers must `.limit(...)` before rendering. Tie-break
  # by id so two snapshots created in the same second (CLI retry) sort stably
  # across SQLite and Postgres.
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

    candidates = screenshots
      .ready
      .where(page_id: page_ids)
      .order(created_at: :desc, id: :desc)
      .includes(screenshot_images: { image_attachment: :blob })

    candidates.each_with_object({}) do |screenshot, acc|
      acc[screenshot.page_id] ||= screenshot
    end
  end

  private

  def default_taken_at
    self.taken_at ||= Time.current
  end

  def normalize_git_commit
    return if git_commit.nil?

    self.git_commit = git_commit.strip.downcase
  end

  def taken_at_not_in_future
    return if taken_at.blank? || taken_at <= Time.current + FUTURE_SKEW

    errors.add(:taken_at, "can't be in the future")
  end
end
