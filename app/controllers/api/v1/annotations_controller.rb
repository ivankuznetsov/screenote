# frozen_string_literal: true

module Api
  module V1
    class AnnotationsController < Api::BaseController
      def index
        return unless require_scope!("mcp_read")

        project = require_current_project!(params[:project_id])
        return unless project

        limit, offset = pagination_params
        annotations = project_annotations(project).order(:created_at)
        annotations = annotations.where(screenshot_id: params[:screenshot_id]) if params[:screenshot_id].present?
        annotations = annotations.where(status: params[:status]) if params[:status].present?
        annotations = annotations.where(viewport: params[:viewport]) if params[:viewport].present?
        total = annotations.count
        annotations = annotations.limit(limit).offset(offset)

        render json: {
          annotations: annotations.map { |a| serialize(a) },
          pagination: { total: total, limit: limit, offset: offset }
        }
      end

      def show
        return unless require_scope!("mcp_read")

        project = require_current_project!(params[:project_id])
        return unless project

        annotation = project_annotations(project).find(params[:id])
        cropped_base64 = begin
          annotation.crop
        rescue => e
          Honeybadger.notify(e, context: {
            annotation_id: annotation.id,
            screenshot_id: annotation.screenshot_id,
            viewport: annotation.viewport
          })
          nil
        end

        render json: Api::V1::ContractSerializer.annotation_detail(annotation, cropped_base64: cropped_base64)
      end

      private

      def project_annotations(project)
        Api::V1::ProjectScope.annotations(project)
      end

      def serialize(annotation)
        Api::V1::ContractSerializer.annotation(annotation)
      end
    end
  end
end
