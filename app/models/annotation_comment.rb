# frozen_string_literal: true

class AnnotationComment < ApplicationRecord
  belongs_to :annotation
  belongs_to :user, optional: true
  belongs_to :api_key, optional: true

  enum :action, { comment: 0, resolved: 1, reopened: 2 }, default: :comment

  validates :body, presence: true, length: { maximum: 5000 }
  validate :has_author

  private

  def has_author
    if user_id.blank? && api_key_id.blank?
      errors.add(:base, "must have a user or api_key")
    end
  end
end
