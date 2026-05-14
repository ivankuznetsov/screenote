# frozen_string_literal: true

class Snapshot < ApplicationRecord
  GIT_COMMIT_FORMAT = /\A[0-9a-f]{7,40}\z/

  belongs_to :project
  has_many :screenshots, dependent: :nullify

  validates :git_commit, presence: true, length: { maximum: 64 }
  validates :taken_at, presence: true

  # Tie-break by id so two snapshots created in the same second
  # (CLI retry) sort stably across SQLite and Postgres.
  scope :recent, -> { order(taken_at: :desc, id: :desc) }

  def short_commit
    git_commit.to_s.first(7)
  end

  def label
    # Server-zone date — Time.zone reflects the request's zone, which is what
    # the dev-facing /snapshot CLI expects (commit date in their local zone).
    "#{taken_at.in_time_zone.to_date.iso8601} · #{short_commit}"
  end
end
