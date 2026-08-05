# frozen_string_literal: true

module Api
  class ScreenshotUploadsController < ActionController::API
    rate_limit to: 20, within: 1.hour, by: -> { request.remote_ip }, with: -> { head :too_many_requests }
    before_action :validate_upload_headers!

    def update
      path_parameters = request.path_parameters
      query_parameters = request.query_parameters
      screenshot = Screenshot.find_by(id: path_parameters[:id])
      unless screenshot
        render json: { error: "Screenshot not found" }, status: :not_found
        return
      end

      # The signed-upload token is issued on a specific ScreenshotImage (any
      # viewport). Resolve via the token rather than hardcoding `:desktop` so
      # multi-viewport uploads can PUT to their own viewport's upload URL.
      # The URL still references the parent Screenshot for URL-shape stability
      # with existing MCP clients.
      screenshot_image = ScreenshotImage.find_by_token_for(:upload, query_parameters[:token])
      unless screenshot_image && screenshot_image.screenshot_id == screenshot.id
        render json: { error: "Invalid or expired upload token" }, status: :unauthorized
        return
      end

      mime_type = query_parameters[:mime_type].presence || request.media_type.presence || "image/png"
      Snapshots::AttachImage.call(
        image: screenshot_image,
        io: request.body,
        declared_content_type: mime_type,
        declared_length: request.content_length
      )

      annotate_url = Rails.application.routes.url_helpers.screenshot_url(
        screenshot,
        Screenote::Deployment.current.url_options
      )

      render json: { success: true, screenshot_id: screenshot.id, annotate_url: annotate_url }, status: :ok
    rescue Snapshots::AttachImage::Error => e
      render json: { error: e.message, code: e.code }, status: e.status
    rescue ActiveRecord::RecordInvalid => e
      render json: { error: e.record.errors.full_messages.join(", ") }, status: :unprocessable_entity
    rescue ActiveRecord::RecordNotUnique
      render json: { error: "Image already uploaded" }, status: :conflict
    end

    private

    def validate_upload_headers!
      if request.content_length && request.content_length > ScreenshotImage::MAX_FILE_SIZE
        render_upload_error("File is too large", code: "file_too_large")
        return
      end

      media_type = request.media_type.to_s.downcase.presence
      query_type = request.query_parameters[:mime_type].to_s.downcase.presence
      unsupported_type = [ media_type, query_type ].compact.find do |content_type|
        !content_type.in?(ScreenshotImage::ALLOWED_CONTENT_TYPES)
      end
      if unsupported_type
        render_upload_error("Invalid mime type. Must be a PNG or JPEG", code: "invalid_content_type")
        return
      end

      return unless media_type && query_type && media_type != query_type

      render_upload_error(
        "Request content type does not match the upload URL content type",
        code: "content_type_mismatch"
      )
    end

    def render_upload_error(message, code:)
      render json: { error: message, code: code }, status: :unprocessable_entity
    end
  end
end
