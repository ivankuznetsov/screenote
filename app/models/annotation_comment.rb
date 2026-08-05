# frozen_string_literal: true

class AnnotationComment < ApplicationRecord
  belongs_to :annotation
  belongs_to :user, optional: true
  belongs_to :api_key, optional: true

  enum :action, { comment: 0, resolved: 1, reopened: 2 }, default: :comment

  validates :body, presence: true, length: { maximum: 5000 }
  validate :has_exactly_one_actor

  private

  def has_exactly_one_actor
    if user_id.blank? && api_key_id.blank?
      errors.add(:base, "must have a user or api_key")
    elsif user_id.present? && api_key_id.present?
      errors.add(:base, "cannot have both user and api_key")
    end
  end
end
