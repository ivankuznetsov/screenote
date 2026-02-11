# frozen_string_literal: true

class Session < ApplicationRecord
  belongs_to :user

  scope :recent, -> { order(created_at: :desc) }
  scope :active, -> { where(created_at: RailsSimpleAuth.configuration.session_expiry.ago..) }
  scope :expired, -> { where(created_at: ...RailsSimpleAuth.configuration.session_expiry.ago) }

  def self.cleanup_expired!
    expired.delete_all
  end
end
