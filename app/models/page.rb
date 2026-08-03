# frozen_string_literal: true

require "uri"

class Page < ApplicationRecord
  belongs_to :project
  has_many :screenshots, dependent: :destroy
  has_one :latest_screenshot, -> {
    where(status: :ready)
      .where(id: Screenshot.where(status: :ready).select("MAX(id)").group(:page_id))
      .order(id: :desc)
  }, class_name: "Screenshot"

  validates :name, presence: true, length: { maximum: 255 }
  validates :name, uniqueness: { scope: :project_id, case_sensitive: false }

  scope :ordered, -> { order(:created_at) }

  def self.display_path_for(value)
    raw_value = value.to_s
    return "" if raw_value.blank?
    return raw_value unless captured_location?(raw_value)

    path = URI.parse(raw_value).path.presence || "/"
    path == "/" ? path : path.chomp("/")
  rescue URI::InvalidURIError
    path = raw_value.split(/[?#]/, 2).first.presence || "/"
    path == "/" ? path : path.chomp("/")
  end

  def self.captured_location?(value)
    value.start_with?("/") || value.match?(/\Ahttps?:\/\//i)
  end
  private_class_method :captured_location?

  def self.normalize_path_prefix(value)
    segments = display_path_for(value).split("/").compact_blank
    "/#{segments.join("/")}" if segments.any?
  end

  def display_path
    self.class.display_path_for(name)
  end

  def path_segments
    display_path.split("/").compact_blank
  end

  def within_path_prefix?(prefix)
    normalized_prefix = self.class.normalize_path_prefix(prefix)
    return false unless normalized_prefix

    normalized_path = "/#{path_segments.join("/")}"
    normalized_path == normalized_prefix || normalized_path.start_with?("#{normalized_prefix}/")
  end

  # Case-insensitive find-or-create that handles concurrent race conditions.
  # Uses LOWER() to match the database index and retries on unique constraint violations.
  def self.find_or_create_by_name!(project, name)
    project.pages.where("LOWER(name) = LOWER(?)", name).first || transaction(requires_new: true) {
      project.pages.create!(name: name)
    }
  rescue ActiveRecord::RecordNotUnique
    project.pages.where("LOWER(name) = LOWER(?)", name).first!
  end
end
