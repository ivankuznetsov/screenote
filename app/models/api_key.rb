# frozen_string_literal: true

class ApiKey < ApplicationRecord
  belongs_to :project

  attr_accessor :raw_token

  validates :token_digest, presence: true, uniqueness: true
  validates :name, presence: true

  scope :active, -> { where(revoked_at: nil) }
  scope :revoked, -> { where.not(revoked_at: nil) }

  before_validation :generate_token, on: :create

  def self.find_by_token(token)
    return nil if token.blank?

    find_by(token_digest: Digest::SHA256.hexdigest(token))
  end

  def revoke!
    update!(revoked_at: Time.current)
  end

  def revoked?
    revoked_at.present?
  end

  def touch_last_used!
    update_column(:last_used_at, Time.current)
  end

  private

  def generate_token
    return if token_digest.present?

    self.raw_token = "sk_proj_#{SecureRandom.hex(24)}"
    self.token_prefix = raw_token.first(12)
    self.token_digest = Digest::SHA256.hexdigest(raw_token)
  end
end
