# frozen_string_literal: true

module Api
  module V1
    class ScreenshotImagesController < Api::BaseController
      include Api::ImageUploadRateLimiting

      UPLOAD_RATE_LIMIT = Api::ImageUploadRateLimiting::UPLOAD_RATE_LIMIT

      rate_limit_image_uploads only: :update
      rescue_from Snapshots::AttachImage::Error do |error|
        render_error(error.message, code: error.code, status: error.status)
      end

      def update
        return unless require_scope!("mcp_write")

        path_parameters = request.path_parameters
        project = require_current_project!(path_parameters[:project_id])
        return unless project

        image = ScreenshotImage.joins(screenshot: :page)
          .where(pages: { project_id: project.id })
          .includes(screenshot: :snapshot)
          .find(path_parameters[:id])
        result = Snapshots::AttachImage.call(
          image: image,
          io: request.body,
          declared_content_type: request.media_type,
          declared_length: request.content_length
        )

        render json: Api::V1::ContractSerializer.screenshot_image_upload(
          result.image,
          operation: result.operation
        )
      end
    end
  end
end
