# frozen_string_literal: true

module Api
  module V1
    class ScreenshotsController < Api::BaseController
      def create
        unless params[:image]
          render json: { error: "Image file is required" }, status: :unprocessable_entity
          return
        end

        screenshot = current_project.screenshots.build(
          title: params[:title].presence || "Untitled"
        )
        screenshot.image.attach(params[:image])

        if screenshot.save
          render json: {
            screenshot_id: screenshot.id,
            annotate_url: screenshot_url(screenshot)
          }, status: :created
        else
          render json: { error: screenshot.errors.full_messages.join(", ") }, status: :unprocessable_entity
        end
      end

      private

      def screenshot_url(screenshot)
        Rails.application.routes.url_helpers.project_screenshot_url(
          current_project, screenshot,
          host: request.host, port: request.port, protocol: request.protocol
        )
      end
    end
  end
end
