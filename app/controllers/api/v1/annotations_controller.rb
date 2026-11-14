# frozen_string_literal: true

module Api
  module V1
    class AnnotationsController < Api::BaseController
      def index
        return unless require_scope!(AuthenticatedPrincipal::READ_SCOPE)

        project = require_current_project!(params[:project_id])
        return unless project

        status = enum_filter_param(:status, Annotation.statuses)
        return if performed?
        viewport = enum_filter_param(:viewport, Annotation.viewports)
        return if performed?

        limit, offset = pagination_params
        annotations = Api::V1::ProjectScope.annotation_list(project).order(:created_at)
        annotations = annotations.where(screenshot_id: params.fetch(:screenshot_id))
        annotations = annotations.where(status: status) if status
        annotations = annotations.where(viewport: viewport) if viewport
        total = annotations.count
        annotations = annotations.limit(limit).offset(offset)

        render json: {
          annotations: Api::V1::ContractSerializer.annotations(annotations),
          pagination: { total: total, limit: limit, offset: offset }
        }
      end

      def show
        return unless require_scope!(AuthenticatedPrincipal::READ_SCOPE)

        project = require_current_project!(params[:project_id])
        return unless project

        annotation = Api::V1::ProjectScope.annotation_details(project).find(params[:id])
        cropped_base64 = begin
          annotation.crop
        rescue => e
          Screenote::Monitoring.notify(e, context: {
            annotation_id: annotation.id,
            screenshot_id: annotation.screenshot_id,
            viewport: annotation.viewport
          })
          nil
        end

        response.set_header("Cache-Control", "private, no-store")
        render json: Api::V1::ContractSerializer.annotation_detail(
          annotation, cropped_base64: cropped_base64, url_options: serializer_url_options
        )
      end
    end
  end
end
