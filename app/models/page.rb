# frozen_string_literal: true

class Page < ApplicationRecord
  belongs_to :project
  has_many :screenshots, dependent: :destroy

  validates :name, presence: true, length: { maximum: 255 }
  validates :name, uniqueness: { scope: :project_id, case_sensitive: false }

  scope :ordered, -> { order(:created_at) }

  # Case-insensitive find-or-create that handles concurrent race conditions.
  # Uses LOWER() to match the database index and retries on unique constraint violations.
  def self.find_or_create_by_name!(project, name)
    project.pages.where("LOWER(name) = LOWER(?)", name).first ||
      project.pages.create!(name: name)
  rescue ActiveRecord::RecordNotUnique
    project.pages.where("LOWER(name) = LOWER(?)", name).first!
  end
end
