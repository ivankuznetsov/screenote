# frozen_string_literal: true

module Api
  module V1
    class ScreenshotImagesController < Api::BaseController
      UPLOAD_RATE_LIMIT = 250

      rate_limit to: UPLOAD_RATE_LIMIT, within: 1.hour, only: :update,
        by: -> {
          if request.authorization.present?
            [ "bearer", Digest::SHA256.hexdigest(request.authorization), params[:project_id] ].join(":")
          else
            [ "ip", request.remote_ip, params[:project_id] ].join(":")
          end
        },
        with: -> { render_error("Too many image uploads", code: "rate_limited", status: :too_many_requests) }

      rescue_from Snapshots::AttachImage::Error do |error|
        render_error(error.message, code: error.code, status: error.status)
      end

      def update
        return unless require_scope!("mcp_write")

        project = require_current_project!(params[:project_id])
        return unless project

        image = ScreenshotImage.joins(screenshot: :page)
          .where(pages: { project_id: project.id })
          .includes(screenshot: :snapshot)
          .find(params[:id])
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
