# frozen_string_literal: true

class OauthDeviceGrant < ApplicationRecord
  DEFAULT_EXPIRES_IN = 10.minutes.to_i
  DEFAULT_POLLING_INTERVAL = 5
  EXPIRED_RETENTION_PERIOD = 15.minutes

  belongs_to :application, class_name: "Doorkeeper::Application"
  belongs_to :resource_owner, class_name: "User", optional: true

  validates :device_code, presence: true, uniqueness: true
  validates :user_code, presence: true, uniqueness: true
  validates :scopes, presence: true
  validates :expires_at, presence: true
  validates :polling_interval, numericality: { only_integer: true, greater_than: 0 }

  scope :expired, -> { where(expires_at: ..Time.current) }
  scope :stale, -> { where(expires_at: ..EXPIRED_RETENTION_PERIOD.ago) }

  class << self
    def digest_device_code(plaintext)
      Digest::SHA256.hexdigest(plaintext.to_s)
    end

    def find_by_plaintext_device_code(plaintext)
      return if plaintext.blank?

      find_by(device_code: digest_device_code(plaintext))
    end

    def normalize_user_code(value)
      characters = value.to_s.upcase.gsub(/[^A-Z0-9]/, "")
      return if characters.length != 10

      "#{characters.first(5)}-#{characters.last(5)}"
    end

    def cleanup_expired!
      stale.delete_all
    end
  end

  def expired?(at: Time.current)
    expires_at <= at
  end

  def approved?
    approved_at.present?
  end

  def denied?
    denied_at.present?
  end
end
