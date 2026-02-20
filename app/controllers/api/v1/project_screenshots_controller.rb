# frozen_string_literal: true

module Api
  module V1
    class ProjectScreenshotsController < Api::V1::BaseController
      before_action :set_project

      def index
        screenshots = @project.screenshots.order(created_at: :desc)

        render json: {
          screenshots: screenshots.map { |s| serialize(s) }
        }
      end

      def create
        screenshot = @project.screenshots.build(
          title: params[:title].presence || "Untitled"
        )

        if params[:image]
          screenshot.image.attach(params[:image])
        end

        if screenshot.save
          render json: serialize(screenshot).merge(
            annotate_url: screenshot_url(screenshot)
          ), status: :created
        else
          render json: { error: screenshot.errors.full_messages.join(", ") }, status: :unprocessable_entity
        end
      end

      private

      def set_project
        @project = current_user.projects.find(params[:project_id])
      rescue ActiveRecord::RecordNotFound
        render json: { error: "Project not found" }, status: :not_found
      end

      def serialize(screenshot)
        {
          id: screenshot.id,
          title: screenshot.title,
          status: screenshot.status,
          annotations_count: screenshot.annotations.count,
          created_at: screenshot.created_at.iso8601
        }
      end

      def screenshot_url(screenshot)
        Rails.application.routes.url_helpers.project_screenshot_url(
          @project, screenshot,
          host: request.host, port: request.port, protocol: request.protocol
        )
      end
    end
  end
end
