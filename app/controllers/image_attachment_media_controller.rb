# frozen_string_literal: true

# Streams attachment bytes after live authorization. Active Storage's public
# routes stay disabled: nothing here redirects to the storage provider, and no
# durable or provider-signed URL ever leaves the application.
class ImageAttachmentMediaController < ApplicationController
  include BlobStreaming

  ALLOWED_VARIANTS = ImageAttachment::MEDIA_VARIANT_NAMES.to_h { |name| [ name.to_s, name ] }.freeze
  DISPOSITIONS = { "download" => :attachment }.freeze

  def show
    attachment = authorized_attachment
    blob = media_blob(attachment, params[:variant])
    raise ActiveRecord::RecordNotFound unless blob

    stream_blob(blob, disposition: DISPOSITIONS.fetch(params[:variant], :inline))
  end

  private

  def authorized_attachment
    attachment = ImageAttachment.with_media.find_by(id: params[:id])
    raise ActiveRecord::RecordNotFound unless attachment
    raise ActiveRecord::RecordNotFound unless attachment.state_ready? && attachment.image.attached?
    raise ActiveRecord::RecordNotFound unless authorized?(attachment)

    attachment
  end

  # Drafts have no message parent yet, so the only possible reader is the
  # person who uploaded them into a live batch. Submitted rows are rechecked
  # against the current project membership on every byte request, which is what
  # makes revoking a collaborator take effect immediately.
  def authorized?(attachment)
    if attachment.draft?
      attachment.user_id == Current.user.id &&
        attachment.image_attachment_batch&.usable? &&
        Current.user.projects.exists?(id: attachment.project_id)
    else
      attachment.parent.present? && Current.user.projects.exists?(id: attachment.project_id)
    end
  end

  def media_blob(attachment, variant_name)
    return attachment.image.blob if %w[original download].include?(variant_name)

    variant_key = ALLOWED_VARIANTS[variant_name]
    return unless variant_key

    # An authenticated GET never invokes libvips. A variant the post-claim
    # warming job has not produced yet simply is not available.
    attachment.image.variant(variant_key).image&.blob
  end
end
