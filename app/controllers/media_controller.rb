# frozen_string_literal: true

class MediaController < ApplicationController
  include BlobStreaming

  ALLOWED_VARIANTS = ScreenshotImage::THUMBNAIL_VARIANT_NAMES.to_h { |name| [ name.to_s, name ] }.freeze

  def show
    screenshot_image = accessible_images.find(params[:id])
    blob = media_blob(screenshot_image, params[:variant])
    raise ActiveRecord::RecordNotFound unless blob

    stream_blob(blob)
  end

  private

  def accessible_images
    ScreenshotImage
      .joins(screenshot: { page: { project: :project_memberships } })
      .where(project_memberships: { user_id: Current.user.id })
      .includes(image_attachment: :blob)
  end

  def media_blob(screenshot_image, variant_name)
    return screenshot_image.image.blob if variant_name == "original" && screenshot_image.image.attached?

    variant_key = ALLOWED_VARIANTS[variant_name]
    return unless variant_key && screenshot_image.image.attached?

    # Never make an authenticated GET trigger image decoding. The warming job
    # creates a tracked record first; a missing record remains unavailable
    # until reconciliation completes it.
    screenshot_image.image.variant(variant_key).image&.blob
  end
end
