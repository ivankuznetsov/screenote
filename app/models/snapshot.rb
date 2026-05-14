# frozen_string_literal: true

class Snapshot < ApplicationRecord
  belongs_to :project
  has_many :screenshots, dependent: :nullify

  validates :git_commit, presence: true, length: { maximum: 64 }
  validates :taken_at, presence: true

  scope :recent, -> { order(taken_at: :desc) }

  def short_commit
    git_commit.to_s.first(7)
  end

  def label
    "#{taken_at.to_date.iso8601} · #{short_commit}"
  end
end
