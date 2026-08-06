# frozen_string_literal: true

class AuthenticationToken < ApplicationRecord
  PURPOSES = {
    invitation: 0,
    password_reset: 1,
    magic_link: 2,
    email_confirmation: 3,
    account_recovery: 4
  }.freeze
  STATES = {
    outstanding: 0,
    consumed: 1,
    superseded: 2,
    cancelled: 3
  }.freeze
  IMMUTABLE_ATTRIBUTES = %i[
    purpose user_id project_invitation_id generation derivation_id
    derivation_key_id token_digest expires_at
  ].freeze
  HEX_64 = /\A[0-9a-f]{64}\z/
  DERIVATION_KEY_ID = /\Av1\.[A-Za-z0-9_-]{43}\z/

  belongs_to :user, optional: true
  belongs_to :project_invitation, optional: true
  belongs_to :issued_by_user, class_name: "User", optional: true

  enum :purpose, PURPOSES, validate: true
  enum :state, STATES, validate: true

  scope :unexpired, -> { where("expires_at > ?", Time.current) }
  scope :active, -> { outstanding.unexpired }

  attr_readonly(*IMMUTABLE_ATTRIBUTES, :issued_by_user_id)

  validates :generation, numericality: { only_integer: true, greater_than: 0 }
  validates :derivation_id, :token_digest,
    presence: true,
    format: { with: HEX_64 }
  validates :derivation_key_id,
    presence: true,
    format: { with: DERIVATION_KEY_ID }
  validates :derivation_id, :token_digest, uniqueness: true
  validate :purpose_matches_subject
  validate :purpose_matches_issuer
  validate :expiry_follows_creation
  validate :state_matches_terminal_at

  def subject
    project_invitation || user
  end

  def subject=(record)
    case record
    when ProjectInvitation
      self.project_invitation = record
      self.user = nil
    when User
      self.user = record
      self.project_invitation = nil
    else
      raise ArgumentError, "authentication token subject must be a User or ProjectInvitation"
    end
  end

  def subject_type
    return "ProjectInvitation" if project_invitation_id

    "User" if user_id
  end

  def subject_id
    project_invitation_id || user_id
  end

  def active?
    outstanding? && expires_at&.future? == true
  end

  def expired?
    expires_at.present? && expires_at <= Time.current
  end

  def terminal?
    !outstanding?
  end

  def transition_to!(terminal_state, at: Time.current)
    value = STATES.fetch(terminal_state.to_sym)
    raise ArgumentError, "outstanding is not a terminal state" if value == STATES.fetch(:outstanding)
    if created_at.present? && at < created_at
      raise ArgumentError, "terminal time cannot precede token creation"
    end

    transitioned = self.class.where(id: id, state: STATES.fetch(:outstanding), terminal_at: nil)
      .update_all(state: value, terminal_at: at, updated_at: at) == 1
    reload if transitioned
    transitioned
  end

  private

  def purpose_matches_subject
    valid =
      if invitation?
        project_invitation_id.present? && user_id.nil?
      elsif purpose.present?
        user_id.present? && project_invitation_id.nil?
      else
        false
      end

    errors.add(:base, "purpose must be bound to its exact subject type") unless valid
  end

  def purpose_matches_issuer
    if account_recovery?
      errors.add(:issued_by_user, "must be present") unless issued_by_user_id.present?
    elsif issued_by_user_id.present?
      errors.add(:issued_by_user, "is only valid for account recovery")
    end
  end

  def expiry_follows_creation
    if expires_at.blank?
      errors.add(:expires_at, "must be present")
    elsif created_at.present? && expires_at <= created_at
      errors.add(:expires_at, "must be after creation")
    end
  end

  def state_matches_terminal_at
    valid = if outstanding?
      terminal_at.nil?
    else
      terminal_at.present? && (created_at.nil? || terminal_at >= created_at)
    end
    errors.add(:terminal_at, "must match token state") unless valid
  end
end
