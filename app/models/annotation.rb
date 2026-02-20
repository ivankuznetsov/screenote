# frozen_string_literal: true

class Annotation < ApplicationRecord
  belongs_to :screenshot
  belongs_to :user
  belongs_to :resolved_by_user, class_name: "User", optional: true
  belongs_to :resolved_by_api_key, class_name: "ApiKey", optional: true
  has_many :annotation_comments, dependent: :destroy

  enum :status, { open: 0, resolved: 1 }, default: :open

  validates :comment, presence: true, length: { maximum: 5000 }
  validates :x_percent, :y_percent, presence: true,
    numericality: { greater_than_or_equal_to: 0.0, less_than_or_equal_to: 100.0 }
  validates :width_percent, :height_percent,
    numericality: { greater_than: 0.0, less_than_or_equal_to: 100.0 }, allow_nil: true
  validate :region_within_bounds

  def point?
    width_percent.nil?
  end

  def reopen!(user:, body:)
    transaction do
      update!(status: :open, resolved_by_user: nil, resolved_by_api_key: nil)
      annotation_comments.create!(user: user, body: body, action: :reopened)
    end
  end

  def resolve!(user: nil, api_key: nil, body: "Marked as resolved")
    transaction do
      self.status = :resolved
      self.resolved_by_user = user if user
      self.resolved_by_api_key = api_key if api_key
      save!
      annotation_comments.create!(
        user: user,
        api_key: api_key,
        body: body,
        action: :resolved
      )
    end
  end

  private

  def region_within_bounds
    if width_percent && x_percent && x_percent + width_percent > 100.0
      errors.add(:width_percent, "annotation extends beyond image boundary")
    end

    if height_percent && y_percent && y_percent + height_percent > 100.0
      errors.add(:height_percent, "annotation extends beyond image boundary")
    end
  end
end
