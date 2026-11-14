# frozen_string_literal: true

class Annotation < ApplicationRecord
  belongs_to :screenshot
  belongs_to :user, optional: true
  belongs_to :api_key, optional: true
  belongs_to :resolved_by_user, class_name: "User", optional: true
  belongs_to :resolved_by_api_key, class_name: "ApiKey", optional: true
  has_many :annotation_comments, -> { order(:created_at) }, dependent: :destroy
  has_many :image_attachments, -> { ordered }, dependent: :destroy, inverse_of: :annotation
  # The claim receipt that made this annotation exists only to answer a
  # replayed submission. It has no meaning once the message is gone.
  has_many :claimed_image_attachment_batches,
    class_name: "ImageAttachmentBatch",
    foreign_key: :claimed_annotation_id,
    inverse_of: :claimed_annotation,
    dependent: :destroy

  enum :status, { open: 0, resolved: 1 }, default: :open
  enum :viewport, { desktop: 0, tablet: 1, mobile: 2 }, default: :desktop, prefix: :viewport

  validates :comment, presence: true, length: { maximum: 5000 }
  validates :x_percent, :y_percent, presence: true,
    numericality: { greater_than_or_equal_to: 0.0, less_than_or_equal_to: 100.0 }
  validates :width_percent, :height_percent,
    numericality: { greater_than: 0.0, less_than_or_equal_to: 100.0 }, allow_nil: true
  validate :has_exactly_one_actor
  validate :resolution_actor_matches_status
  validate :region_dimensions_paired, if: :region_dimensions_changing?
  validate :region_within_bounds

  def point?
    width_percent.nil?
  end

  # Returns a Base64-encoded PNG crop of this annotation's region from the
  # matching ScreenshotImage (same viewport), or nil if the image is missing
  # or not yet analyzed. Cached via AnnotationCropService.
  def crop
    target = screenshot.image_for(viewport)
    return unless target&.status_ready? && target.image.attached?

    AnnotationCropService.crop(target, self)
  end

  # List reads pass `comments_count` from one grouped count for the whole
  # page (Api::V1::ProjectScope.comment_counts) instead of loading comments.
  def as_api_json(comments_count: annotation_comments.size)
    {
      id: id,
      screenshot_id: screenshot_id,
      viewport: viewport,
      type: point? ? "point" : "region",
      coordinates: {
        x_percent: x_percent,
        y_percent: y_percent,
        width_percent: width_percent,
        height_percent: height_percent
      },
      comment: comment,
      status: status,
      author: user&.email || api_key&.name,
      comments_count: comments_count,
      created_at: created_at.iso8601
    }
  end

  def reopen!(user: nil, api_key: nil, body:)
    with_lock do
      raise ActiveRecord::RecordNotFound, "Annotation is not resolved" unless resolved?

      update!(status: :open, resolved_by_user: nil, resolved_by_api_key: nil)
      annotation_comments.create!(user: user, api_key: api_key, body: body, action: :reopened)
    end
  end

  def resolve!(user: nil, api_key: nil, body: "Marked as resolved")
    with_lock do
      raise ActiveRecord::RecordNotFound, "Annotation is not open" unless open?

      create_resolution!(user: user, api_key: api_key, body: body)
    end
  end

  def resolve_idempotently!(user: nil, api_key: nil, body: "Marked as resolved")
    with_lock do
      if resolved?
        [ "already_resolved", latest_resolution_comment ]
      else
        [ "resolved", create_resolution!(user: user, api_key: api_key, body: body) ]
      end
    end
  end

  private

  def create_resolution!(user:, api_key:, body:)
    update!(status: :resolved, resolved_by_user: user, resolved_by_api_key: api_key)
    annotation_comments.create!(user: user, api_key: api_key, body: body, action: :resolved)
  end

  def latest_resolution_comment
    annotation_comments.where(action: :resolved).order(:created_at, :id).last
  end

  def has_exactly_one_actor
    if user_id.blank? && api_key_id.blank?
      errors.add(:base, "must have a user or api_key actor")
    elsif user_id.present? && api_key_id.present?
      errors.add(:base, "cannot have both user and api_key actors")
    end
  end

  def resolution_actor_matches_status
    resolvers = [ resolved_by_user_id, resolved_by_api_key_id ].compact

    if open?
      errors.add(:base, "open annotation cannot have a resolution actor") if resolvers.any?
      return
    end

    errors.add(:base, "resolved annotation must have exactly one resolution actor") unless resolvers.one?
  end

  # A region needs both dimensions; one alone is neither a point nor a
  # croppable region. Checked whenever a dimension is written, so an older
  # half-specified row can still be resolved or reopened.
  def region_dimensions_paired
    return if width_percent.nil? == height_percent.nil?

    missing, given = width_percent.nil? ? %w[width_percent height_percent] : %w[height_percent width_percent]
    errors.add(missing, "is required when #{given} is given")
  end

  def region_dimensions_changing?
    new_record? || will_save_change_to_width_percent? || will_save_change_to_height_percent?
  end

  def region_within_bounds
    if width_percent && x_percent && x_percent + width_percent > 100.0
      errors.add(:width_percent, "annotation extends beyond image boundary")
    end

    if height_percent && y_percent && y_percent + height_percent > 100.0
      errors.add(:height_percent, "annotation extends beyond image boundary")
    end
  end
end
