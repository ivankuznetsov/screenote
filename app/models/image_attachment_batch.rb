# frozen_string_literal: true

# A server-owned draft container for one mounted browser composer. The public
# ID is the only identifier the browser ever sees: it addresses the draft and
# doubles as the one-use submission idempotency key when the composer posts.
class ImageAttachmentBatch < ApplicationRecord
  EXPIRY = 24.hours
  MAX_OPEN_PER_USER = 6
  # Scheduler-independent backstop. Cleanup normally reclaims drafts long
  # before this, but a stopped supervisor must not let one account park an
  # unbounded number of bytes in the storage service.
  MAX_OUTSTANDING_DRAFT_BYTES = 250.megabytes
  PUBLIC_ID_FORMAT = /\A[A-Za-z0-9_-]{22,43}\z/

  belongs_to :user
  belongs_to :project
  belongs_to :claimed_annotation, class_name: "Annotation", optional: true
  belongs_to :claimed_annotation_comment, class_name: "AnnotationComment", optional: true
  has_many :image_attachments, dependent: :destroy

  enum :state, { open: 0, claimed: 1 }, default: :open, prefix: :state

  before_validation :assign_public_id, on: :create
  before_validation :assign_activity_window, on: :create

  validates :public_id, presence: true, uniqueness: true, format: { with: PUBLIC_ID_FORMAT }
  validate :claim_target_matches_state

  scope :expired, ->(now = Time.current) { where(expires_at: ...now) }
  scope :outstanding, -> { where(state: :open) }

  def self.generate_public_id
    SecureRandom.urlsafe_base64(24)
  end

  def to_param
    public_id
  end

  def expired?(now = Time.current)
    expires_at.nil? || expires_at <= now
  end

  # A batch accepts uploads and can still be claimed only while it is open and
  # inside its activity window.
  def usable?(now = Time.current)
    state_open? && !expired?(now)
  end

  def claimed_parent
    claimed_annotation || claimed_annotation_comment
  end

  def touch_activity!(now = Time.current)
    update_columns(last_activity_at: now, expires_at: now + EXPIRY, updated_at: now)
  end

  def total_byte_size(excluding: nil)
    scope = image_attachments
    scope = scope.where.not(id: excluding) if excluding
    scope.sum(:byte_size)
  end

  private

  def assign_public_id
    self.public_id = self.class.generate_public_id if public_id.blank?
  end

  def assign_activity_window
    now = Time.current
    self.last_activity_at ||= now
    self.expires_at ||= last_activity_at + EXPIRY
  end

  def claim_target_matches_state
    targets = [ claimed_annotation_id, claimed_annotation_comment_id ].compact

    if state_open?
      errors.add(:base, "open batch cannot reference a claimed parent") if targets.any?
    elsif !targets.one?
      errors.add(:base, "claimed batch must reference exactly one parent")
    end
  end
end
