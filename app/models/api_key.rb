# frozen_string_literal: true

class ApiKey < ApplicationRecord
  belongs_to :project

  validates :token, presence: true, uniqueness: true
  validates :name, presence: true

  scope :active, -> { where(revoked_at: nil) }
  scope :revoked, -> { where.not(revoked_at: nil) }

  before_validation :generate_token, on: :create

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
    self.token = "sk_proj_#{SecureRandom.hex(24)}" if token.blank?
  end
end
