# frozen_string_literal: true

module Api
  module V1
    class AnnotationsController < Api::BaseController
      def index
        annotations = project_annotations.order(:created_at)
        annotations = annotations.where(screenshot_id: params[:screenshot_id]) if params[:screenshot_id].present?
        annotations = annotations.where(status: params[:status]) if params[:status].present?

        render json: {
          annotations: annotations.map { |a| serialize(a) }
        }
      end

      private

      def project_annotations
        Annotation.joins(screenshot: :project)
          .where(projects: { id: current_project.id })
          .includes(:user, :screenshot)
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
