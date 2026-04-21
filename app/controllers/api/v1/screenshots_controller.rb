# frozen_string_literal: true

module Api
  module V1
    class ScreenshotsController < Api::BaseController
      def create
        unless params[:image]
          render json: { error: "Image file is required" }, status: :unprocessable_entity
          return
        end

        title = params[:title].presence || "Untitled"
        page = Page.find_or_create_by_name!(current_project, title)
        screenshot = Screenshot.create_with_image!(
          page: page, title: title,
          io: params[:image].tempfile,
          filename: params[:image].original_filename,
          content_type: params[:image].content_type
        )

        render json: {
          screenshot_id: screenshot.id,
          annotate_url: screenshot_url(screenshot)
        }, status: :created
      rescue ActiveRecord::RecordInvalid => e
        render json: { error: e.record.errors.full_messages.join(", ") }, status: :unprocessable_entity
      end

      private

      def screenshot_url(screenshot)
        Rails.application.routes.url_helpers.screenshot_url(
          screenshot,
          host: request.host, port: request.port, protocol: request.protocol
        )
      end
    end
  end
end
