# frozen_string_literal: true

class MediaController < ApplicationController
  include BlobStreaming

  ALLOWED_VARIANTS = ScreenshotImage::THUMBNAIL_VARIANT_NAMES.to_h { |name| [ name.to_s, name ] }.freeze

  def show
    screenshot_image = accessible_images.find(params[:id])
    blob = resolve_variant_blob(screenshot_image.image, params[:variant], allowed: ALLOWED_VARIANTS)
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
end
