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

      unless Screenshot.find_by_token_for(:upload, params[:token]) == screenshot
        render json: { error: "Invalid or expired upload token" }, status: :unauthorized
        return
      end

      if screenshot.image.attached?
        render json: { error: "Image already uploaded" }, status: :conflict
        return
      end

      mime_type = params[:mime_type].presence || "image/png"
      unless mime_type.in?(Screenshot::ALLOWED_CONTENT_TYPES)
        render json: { error: "Invalid mime type. Must be image/png or image/jpeg" }, status: :unprocessable_entity
        return
      end

      body = request.body.read
      if body.blank?
        render json: { error: "Request body is empty" }, status: :unprocessable_entity
        return
      end

      if body.bytesize > Screenshot::MAX_FILE_SIZE
        render json: { error: "File too large (max #{Screenshot::MAX_FILE_SIZE / 1.megabyte}MB)" }, status: :unprocessable_entity
        return
      end

      extension = mime_type == "image/jpeg" ? "jpg" : "png"
      screenshot.image.attach(
        io: StringIO.new(body),
        filename: "screenshot.#{extension}",
        content_type: mime_type
      )

      ScreenshotDimensionJob.perform_later(screenshot)

      annotate_url = Rails.application.routes.url_helpers.project_screenshot_url(
        screenshot.project, screenshot
      )

      render json: { success: true, screenshot_id: screenshot.id, annotate_url: annotate_url }, status: :ok
    rescue ActiveRecord::RecordNotUnique
      render json: { error: "Image already uploaded" }, status: :conflict
    end
  end
end
