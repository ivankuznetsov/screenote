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
          .includes(:user, :screenshot, :annotation_comments)
      end

      def serialize(annotation)
        annotation.as_api_json
      end
    end
  end
end
