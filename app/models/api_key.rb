# frozen_string_literal: true

class ApiKey < ApplicationRecord
  belongs_to :project
  belongs_to :issued_by_user, class_name: "User", inverse_of: false, optional: true

  has_many :annotations, dependent: :restrict_with_error
  has_many :resolved_annotations,
    class_name: "Annotation",
    foreign_key: :resolved_by_api_key_id,
    inverse_of: :resolved_by_api_key,
    dependent: :restrict_with_error
  has_many :annotation_comments, dependent: :restrict_with_error

  attr_accessor :raw_token

  attr_readonly :token_digest, :token_prefix, :issued_by_user_id

  validates :token_digest, presence: true, uniqueness: true
  validates :name, presence: true, length: { maximum: 255 }
  validates :issued_by_user, presence: true, on: :create
  validate :issued_by_project_owner, on: :create

  scope :active, -> { where(revoked_at: nil) }
  scope :revoked, -> { where.not(revoked_at: nil) }

  before_validation :generate_token, on: :create

  def self.find_by_token(token)
    return nil if token.blank?

    find_by(token_digest: Digest::SHA256.hexdigest(token))
  end

  def revoke!
    return if revoked?

    update!(revoked_at: Time.current)
  end

  def revoked?
    revoked_at.present?
  end

  def touch_last_used!
    return if last_used_at.present? && last_used_at > 5.minutes.ago

    update_column(:last_used_at, Time.current)
  end

  private

  def generate_token
    return if token_digest.present?

    self.raw_token = "sk_proj_#{SecureRandom.hex(24)}"
    self.token_prefix = raw_token.first(12)
    self.token_digest = Digest::SHA256.hexdigest(raw_token)
  end

  def issued_by_project_owner
    return if project.blank? || issued_by_user.blank?
    return if project.project_memberships.exists?(user_id: issued_by_user_id, role: :owner)

    errors.add(:issued_by_user, "must be an owner of the project")
  end
end
