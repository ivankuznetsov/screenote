# frozen_string_literal: true

module Api
  class ScreenshotUploadsController < ActionController::API
    rate_limit to: 20, within: 1.hour, by: -> { request.remote_ip }, with: -> { head :too_many_requests }

    def update
      screenshot = Screenshot.find_by(id: params[:id])
      unless screenshot
        render json: { error: "Screenshot not found" }, status: :not_found
        return
      end

      # The signed-upload token is issued on the :desktop ScreenshotImage (see
      # CreateScreenshotUploadTool). The URL still references the parent
      # Screenshot for URL-shape stability with existing MCP clients.
      screenshot_image = screenshot.screenshot_images.find_by(viewport: :desktop)
      unless screenshot_image
        render json: { error: "Screenshot not found" }, status: :not_found
        return
      end

      unless ScreenshotImage.find_by_token_for(:upload, params[:token]) == screenshot_image
        render json: { error: "Invalid or expired upload token" }, status: :unauthorized
        return
      end

      if screenshot_image.image.attached?
        render json: { error: "Image already uploaded" }, status: :conflict
        return
      end

      mime_type = params[:mime_type].presence || "image/png"
      unless mime_type.in?(ScreenshotImage::ALLOWED_CONTENT_TYPES)
        render json: { error: "Invalid mime type. Must be image/png or image/jpeg" }, status: :unprocessable_entity
        return
      end

      body = request.body.read
      if body.blank?
        render json: { error: "Request body is empty" }, status: :unprocessable_entity
        return
      end

      if body.bytesize > ScreenshotImage::MAX_FILE_SIZE
        render json: { error: "File too large (max #{ScreenshotImage::MAX_FILE_SIZE / 1.megabyte}MB)" }, status: :unprocessable_entity
        return
      end

      extension = mime_type == "image/jpeg" ? "jpg" : "png"
      screenshot_image.image.attach(
        io: StringIO.new(body),
        filename: "screenshot.#{extension}",
        content_type: mime_type
      )
      # Explicit save! so acceptable_image validators run and surface errors
      # (todo 166 — security review finding on PR-1).
      screenshot_image.save!

      ScreenshotDimensionJob.perform_later(screenshot_image)

      annotate_url = Rails.application.routes.url_helpers.screenshot_url(screenshot)

      render json: { success: true, screenshot_id: screenshot.id, annotate_url: annotate_url }, status: :ok
    rescue ActiveRecord::RecordInvalid => e
      render json: { error: e.record.errors.full_messages.join(", ") }, status: :unprocessable_entity
    rescue ActiveRecord::RecordNotUnique
      render json: { error: "Image already uploaded" }, status: :conflict
    end
  end
end
