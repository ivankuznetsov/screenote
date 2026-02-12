# frozen_string_literal: true

class Annotation < ApplicationRecord
  belongs_to :screenshot
  belongs_to :user
  belongs_to :resolved_by_user, class_name: "User", optional: true
  belongs_to :resolved_by_api_key, class_name: "ApiKey", optional: true

  enum :status, { open: 0, resolved: 1 }, default: :open

  validates :x_percent, :y_percent, presence: true,
    numericality: { greater_than_or_equal_to: 0.0, less_than_or_equal_to: 100.0 }
  validates :width_percent, :height_percent,
    numericality: { greater_than: 0.0, less_than_or_equal_to: 100.0 }, allow_nil: true
  validate :region_within_bounds

  def point?
    width_percent.nil?
  end

  private

  def region_within_bounds
    return unless width_percent && x_percent

    if x_percent + width_percent > 100.0
      errors.add(:width_percent, "annotation extends beyond image boundary")
    end

    return unless height_percent && y_percent && y_percent + height_percent > 100.0

    errors.add(:height_percent, "annotation extends beyond image boundary")
  end
end
