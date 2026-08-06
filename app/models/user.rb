# frozen_string_literal: true

class User < ApplicationRecord
  include RailsSimpleAuth::Models::Concerns::Authenticatable
  include RailsSimpleAuth::Models::Concerns::Confirmable

  undef_method :generate_password_reset_token
  undef_method :generate_magic_link_token
  undef_method :generate_confirmation_token

  OauthIdentity = Data.define(:provider, :uid, :email) do
    def inspect
      "#<#{self.class.name} provider=#{provider.inspect} [FILTERED]>"
    end

    alias_method :to_s, :inspect

    def as_json(*)
      "[FILTERED]"
    end
  end
  OAUTH_PROVIDERS = %w[google_oauth2 github].freeze

  has_many :sessions, dependent: :destroy
  has_many :owned_projects, class_name: "Project", foreign_key: :user_id, inverse_of: :creator, dependent: :destroy
  has_many :project_memberships, dependent: :destroy
  has_many :projects, through: :project_memberships
  has_many :annotations, dependent: :destroy
  has_one :subscription, dependent: :destroy
  has_many :authentication_tokens, dependent: :destroy
  has_many :installation_audit_events_as_actor,
    class_name: "InstallationAuditEvent",
    foreign_key: :actor_user_id,
    inverse_of: :actor_user,
    dependent: :restrict_with_exception
  has_many :installation_audit_events_as_target,
    class_name: "InstallationAuditEvent",
    foreign_key: :target_user_id,
    inverse_of: :target_user,
    dependent: :restrict_with_exception

  enum :access_status, { active: 0, suspended: 1 }, validate: true

  validates :oauth_provider, :oauth_uid, presence: true, if: :oauth_identity_present?
  validates :oauth_uid, uniqueness: { scope: :oauth_provider }, allow_nil: true
  validate :oauth_identity_is_paired

  normalizes :oauth_provider, with: ->(provider) { provider.strip.downcase.presence }
  normalizes :oauth_uid, with: ->(uid) { uid.strip.presence }

  def pro?(deployment: Screenote::Deployment.current)
    return false unless deployment.billing?

    subscription&.active_pro?
  end

  def access_active?
    active?
  end

  alias_method :active_for_authentication?, :access_active?

  def can_create_project?(deployment: Screenote::Deployment.current)
    return true unless deployment.billing?

    pro?(deployment: deployment) || owned_projects.count < Subscription::FREE_PROJECT_LIMIT
  end

  def can_invite_member?(project, deployment: Screenote::Deployment.current)
    return true unless deployment.billing?

    pro?(deployment: deployment) ||
      project.project_memberships.where(role: :member).count < Subscription::FREE_MEMBER_LIMIT
  end

  def saas_operator?(deployment: Screenote::Deployment.current)
    deployment.saas? && email == deployment.saas_operator_email
  end

  def assign_oauth_attributes(auth_hash)
    self.oauth_provider = auth_hash["provider"]
    self.oauth_uid = auth_hash["uid"]
  end

  class << self
    def find_by_oauth(provider, uid)
      find_by(oauth_provider: provider.to_s.strip.downcase, oauth_uid: uid.to_s.strip)
    end

    def verified_oauth_identity(auth_hash)
      provider = oauth_value(auth_hash, "provider").to_s.strip.downcase
      uid = oauth_value(auth_hash, "uid").to_s.strip
      info = oauth_value(auth_hash, "info") || {}
      email = oauth_value(info, "email").to_s.strip.downcase
      return unless OAUTH_PROVIDERS.include?(provider) && uid.present?
      return unless email.match?(URI::MailTo::EMAIL_REGEXP)

      verified = if provider == "google_oauth2"
        oauth_value(info, "email_verified") == true
      else
        github_verified_primary_email?(auth_hash, email)
      end
      OauthIdentity.new(provider:, uid:, email:) if verified
    end

    def authenticate_verified_oauth(auth_hash, allow_create:)
      identity = verified_oauth_identity(auth_hash)
      return unless identity

      exact = find_by_oauth(identity.provider, identity.uid)
      return exact if exact&.access_active? && exact.email == identity.email
      return unless allow_create

      create_verified_oauth_user(identity)
    end

    private

    def create_verified_oauth_user(identity)
      DatabaseRetry.call do
        transaction do
          normalized_email = AdmissionLock.email!(identity.email)
          oauth_user = find_by_oauth(identity.provider, identity.uid)
          email_users = where(email: normalized_email).order(:id).to_a
          locked = AuthorityLock.users!([ oauth_user, *email_users ].compact).index_by(&:id)
          oauth_user = locked[oauth_user.id] if oauth_user

          if oauth_user
            next oauth_user if oauth_user.access_active? && oauth_user.email == normalized_email

            next nil
          end
          next nil if email_users.any?

          create!(
            email: normalized_email,
            password: SecureRandom.base64(32),
            confirmed_at: Time.current,
            access_status: :active,
            oauth_provider: identity.provider,
            oauth_uid: identity.uid
          )
        end
      end
    rescue DatabaseRetry::Exhausted, ActiveRecord::ActiveRecordError
      exact = find_by_oauth(identity.provider, identity.uid)
      exact if exact&.access_active? && exact.email == identity.email
    end

    def github_verified_primary_email?(auth_hash, email)
      extra = oauth_value(auth_hash, "extra") || {}
      emails = oauth_value(extra, "all_emails")
      return false unless emails.is_a?(Array)

      emails.any? do |candidate|
        oauth_value(candidate, "primary") == true &&
          oauth_value(candidate, "verified") == true &&
          oauth_value(candidate, "email").to_s.strip.downcase == email
      end
    end

    def oauth_value(hash, key)
      return unless hash.respond_to?(:[])

      hash[key] || hash[key.to_sym]
    end
  end

  private

  def oauth_identity_present?
    oauth_provider.present? || oauth_uid.present?
  end

  def oauth_identity_is_paired
    return if oauth_provider.blank? == oauth_uid.blank?

    errors.add(:oauth_provider, "and OAuth UID must both be present or both be absent")
  end
end
