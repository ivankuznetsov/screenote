# frozen_string_literal: true

module Api
  module V1
    class ScreenshotAnnotationsController < Api::V1::BaseController
      before_action :set_screenshot

      def index
        annotations = @screenshot.annotations.includes(:user).order(:created_at)
        annotations = annotations.where(status: params[:status]) if params[:status].present?

        render json: {
          annotations: annotations.map { |a| serialize(a) }
        }
      end

      def create
        annotation = @screenshot.annotations.build(annotation_params)
        annotation.user = current_user

        if annotation.save
          render json: serialize(annotation), status: :created
        else
          render json: { error: annotation.errors.full_messages.join(", ") }, status: :unprocessable_entity
        end
      end

      def update
        annotation = @screenshot.annotations.find(params[:id])
        annotation.assign_attributes(annotation_params)
        annotation.resolved_by_user = current_user if annotation.status_changed? && annotation.resolved?

        if annotation.save
          render json: serialize(annotation)
        else
          render json: { error: annotation.errors.full_messages.join(", ") }, status: :unprocessable_entity
        end
      end

      private

      def set_screenshot
        project = current_user.projects.find(params[:project_id])
        @screenshot = project.screenshots.find(params[:screenshot_id])
      rescue ActiveRecord::RecordNotFound
        render json: { error: "Not found" }, status: :not_found
      end

      def annotation_params
        params.permit(:x_percent, :y_percent, :width_percent, :height_percent, :comment, :status)
      end

      def serialize(annotation)
        {
          id: annotation.id,
          screenshot_id: annotation.screenshot_id,
          type: annotation.point? ? "point" : "region",
          coordinates: {
            x_percent: annotation.x_percent,
            y_percent: annotation.y_percent,
            width_percent: annotation.width_percent,
            height_percent: annotation.height_percent
          },
          comment: annotation.comment,
          status: annotation.status,
          author: annotation.user&.email,
          created_at: annotation.created_at.iso8601
        }
      end
    end
  end
end
