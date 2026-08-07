# frozen_string_literal: true

class OauthDeviceGrant < ApplicationRecord
  DEFAULT_EXPIRES_IN = 10.minutes.to_i
  DEFAULT_POLLING_INTERVAL = 5
  EXPIRED_RETENTION_PERIOD = 15.minutes

  belongs_to :application, class_name: "Doorkeeper::Application"
  belongs_to :resource_owner, class_name: "User", optional: true
  belongs_to :project, optional: true

  validates :device_code, presence: true, uniqueness: true
  validates :user_code, presence: true, uniqueness: true
  validates :scopes, presence: true
  validates :expires_at, presence: true
  validates :polling_interval, numericality: { only_integer: true, greater_than: 0 }
  validate :principal_binding_is_consistent
  validate :approved_principal_is_immutable, on: :update

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

  private

  def principal_binding_is_consistent
    if approved?
      unless resource_owner && Oauth::PrincipalBinding.valid?(self)
        errors.add(:principal_kind, "must identify authority the resource owner currently holds")
      end
    elsif principal_kind.present? || project_id.present?
      errors.add(:principal_kind, "cannot be selected before approval")
    end
  end

  def approved_principal_is_immutable
    return if principal_kind_in_database.blank?
    return unless will_save_change_to_principal_kind? || will_save_change_to_project_id? ||
      will_save_change_to_resource_owner_id?

    errors.add(:principal_kind, "cannot change after approval")
  end
end
