# frozen_string_literal: true

class InstallationAuditEvent < ApplicationRecord
  belongs_to :installation
  belongs_to :actor_user, class_name: "User", optional: true
  belongs_to :target_user, class_name: "User", optional: true

  validates :event_type,
    presence: true,
    format: { with: /\A[a-z][a-z0-9_]*\z/ }
  validate :metadata_is_an_object

  normalizes :event_type, with: ->(event_type) { event_type.strip.downcase }

  def readonly?
    persisted?
  end

  private

  def metadata_is_an_object
    errors.add(:metadata, "must be an object") unless metadata.is_a?(Hash)
  end
end
