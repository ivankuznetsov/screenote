# frozen_string_literal: true

class Installation < ApplicationRecord
  SINGLETON_KEY = "screenote"
  DEPLOYMENT_MODES = %w[saas self_hosted].freeze
  STATES = %w[saas unclaimed claimed].freeze
  STORAGE_SERVICES = %w[rabata self_hosted_local self_hosted_s3].freeze

  belongs_to :administrator, class_name: "User", optional: true

  attr_readonly :singleton_key, :deployment_mode, :storage_service, :storage_namespace_fingerprint

  validates :singleton_key, inclusion: { in: [ SINGLETON_KEY ] }, uniqueness: true
  validates :deployment_mode, inclusion: { in: DEPLOYMENT_MODES }
  validates :state, inclusion: { in: STATES }
  validates :storage_service, inclusion: { in: STORAGE_SERVICES }
  validates :storage_namespace_fingerprint,
    presence: true,
    length: { is: 64 },
    format: { with: /\A[0-9a-f]{64}\z/ }
  validates :bootstrap_token_digest,
    length: { is: 64 },
    format: { with: /\A[0-9a-f]{64}\z/ },
    allow_nil: true
  validate :state_matches_deployment
  validate :storage_matches_deployment

  class << self
    def current
      find_by(singleton_key: SINGLETON_KEY)
    end

    def current!
      find_by!(singleton_key: SINGLETON_KEY)
    end
  end

  def saas?
    deployment_mode == "saas"
  end

  def self_hosted?
    deployment_mode == "self_hosted"
  end

  def claimed?
    state == "claimed"
  end

  def unclaimed?
    state == "unclaimed"
  end

  private

  def state_matches_deployment
    valid =
      case deployment_mode
      when "saas"
        state == "saas" && administrator_id.nil? && bootstrap_token_digest.nil? && claimed_at.nil?
      when "self_hosted"
        if state == "unclaimed"
          administrator_id.nil? && bootstrap_token_digest.present? && claimed_at.nil?
        elsif state == "claimed"
          administrator_id.present? && bootstrap_token_digest.nil? && claimed_at.present?
        else
          false
        end
      else
        false
      end

    errors.add(:state, "does not match the deployment ownership state") unless valid
  end

  def storage_matches_deployment
    valid =
      if deployment_mode == "saas"
        storage_service == "rabata"
      elsif deployment_mode == "self_hosted"
        %w[self_hosted_local self_hosted_s3].include?(storage_service)
      else
        false
      end

    errors.add(:storage_service, "does not match the deployment mode") unless valid
  end
end
