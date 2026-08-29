# frozen_string_literal: true

# One uploaded image belonging to a native browser message. While a row is a
# draft it belongs to an ImageAttachmentBatch and has no message parent. After
# the composer posts, it belongs to exactly one Annotation or AnnotationComment
# and is immutable.
class ImageAttachment < ApplicationRecord
  ALLOWED_CONTENT_TYPES = %w[image/png image/jpeg image/webp].freeze
  ALLOWED_EXTENSIONS = {
    "image/png" => %w[png].freeze,
    "image/jpeg" => %w[jpg jpeg].freeze,
    "image/webp" => %w[webp].freeze
  }.freeze
  MAX_FILE_SIZE = 20.megabytes
  MAX_TOTAL_BYTES = 50.megabytes
  MAX_FILES = 5
  MAX_DIMENSION = 32_768
  MAX_PIXELS = 50_000_000
  MAX_ALT_TEXT = 1000
  ALT_TEXT_FALLBACK = "Attached image"
  THUMBNAIL_VARIANT_NAMES = %i[attachment_thumb_1x attachment_thumb_2x].freeze
  MEDIA_VARIANT_NAMES = (THUMBNAIL_VARIANT_NAMES + %i[original download]).freeze
  MEDIA_TOKEN_PURPOSE = :image_attachment_media
  MEDIA_TOKEN_EXPIRY = 5.minutes
  # Every attachment read is authorized live. The purpose token only bounds how
  # long a minted URL stays usable; it never carries authority on its own.
  generates_token_for MEDIA_TOKEN_PURPOSE, expires_in: MEDIA_TOKEN_EXPIRY

  belongs_to :image_attachment_batch, optional: true
  belongs_to :annotation, optional: true
  belongs_to :annotation_comment, optional: true
  belongs_to :user
  belongs_to :project

  has_one_attached :image do |attachable|
    attachable.variant :attachment_thumb_1x, resize_to_limit: [ 480, 480 ]
    attachable.variant :attachment_thumb_2x, resize_to_limit: [ 960, 960 ]
  end

  enum :state, { uploading: 0, ready: 1, failed: 2 }, default: :uploading, prefix: :state

  normalizes :alt_text, with: ->(value) { value.to_s.strip.presence }

  validates :client_key, presence: true, length: { maximum: 64 }
  validates :alt_text, length: { maximum: MAX_ALT_TEXT }, allow_nil: true
  validates :media_type, inclusion: { in: ALLOWED_CONTENT_TYPES }, allow_nil: true
  validates :width, :height, numericality: { only_integer: true, greater_than: 0 }, allow_nil: true
  validates :byte_size,
    numericality: { only_integer: true, greater_than: 0, less_than_or_equal_to: MAX_FILE_SIZE },
    allow_nil: true
  validate :exactly_one_owner
  validate :submitted_rows_are_complete
  validate :identity_is_immutable
  validate :submitted_metadata_is_immutable

  scope :submitted, -> { where(image_attachment_batch_id: nil) }
  scope :drafts, -> { where.not(image_attachment_batch_id: nil) }
  scope :ordered, -> { order(:id) }
  scope :with_media, -> { includes(image_attachment: :blob) }

  def draft?
    image_attachment_batch_id.present?
  end

  def submitted?
    !draft?
  end

  def parent
    annotation || annotation_comment
  end

  def display_alt_text
    alt_text.presence || ALT_TEXT_FALLBACK
  end

  # Rendering never triggers image processing. A variant that the post-claim
  # warming job has not produced yet is simply not available for delivery.
  def thumbnail_variant_ready?(name)
    return false unless image.attached?
    return false unless THUMBNAIL_VARIANT_NAMES.include?(name.to_sym)

    digest = image.variant(name.to_sym).variation.digest
    image.blob.variant_records.exists?(variation_digest: digest)
  end

  def thumbnail_variants_warmed?
    return false unless image.attached?

    THUMBNAIL_VARIANT_NAMES.all? { |name| thumbnail_variant_ready?(name) }
  end

  def as_contract_json(url: nil, url_expires_at: nil)
    {
      id: id,
      alt_text: alt_text,
      media_type: media_type,
      width: width,
      height: height,
      size: byte_size,
      url: url,
      url_expires_at: url_expires_at&.iso8601
    }
  end

  private

  def exactly_one_owner
    owners = [ image_attachment_batch_id, annotation_id, annotation_comment_id ].compact
    return if owners.one?

    errors.add(:base, "must belong to exactly one draft batch or message")
  end

  def submitted_rows_are_complete
    return if draft?

    errors.add(:state, "submitted attachment must be ready") unless state_ready?
    return unless state_ready?

    errors.add(:base, "submitted attachment is missing image metadata") if media_type.blank? ||
      width.blank? || height.blank? || byte_size.blank?
  end

  def identity_is_immutable
    return if new_record?

    errors.add(:user_id, "cannot change") if will_save_change_to_user_id?
    errors.add(:project_id, "cannot change") if will_save_change_to_project_id?
  end

  # Once a message owns the row, the stored bytes and their description are the
  # historical record of what was posted.
  def submitted_metadata_is_immutable
    return if new_record?
    return if image_attachment_batch_id_in_database.present?

    %i[alt_text media_type width height byte_size state annotation_id annotation_comment_id].each do |attribute|
      errors.add(attribute, "cannot change after submission") if will_save_change_to_attribute?(attribute)
    end
  end
end
