# frozen_string_literal: true

module Api
  module V1
    class AnnotationResolutionsController < Api::BaseController
      def create
        return unless require_scope!("mcp_write")

        project = require_current_project!(params[:project_id])
        return unless project

        annotation = Api::V1::ProjectScope.annotations(project).find(params[:annotation_id])
        return unless valid_comment_param?

        operation, comment = annotation.resolve_idempotently!(
          user: current_user,
          api_key: current_api_key,
          body: params[:comment].presence || "Marked as resolved"
        )

        render json: {
          success: true,
          operation: operation,
          annotation: Api::V1::ContractSerializer.annotation(annotation.reload),
          comment: comment && Api::V1::ContractSerializer.annotation_comment(comment, annotation: annotation)
        }
      end

      private

      def valid_comment_param?
        return true if params[:comment].nil? || params[:comment].is_a?(String)

        render_error(
          "Comment must be a string",
          code: "validation_failed",
          status: :unprocessable_entity,
          details: [ "Comment must be a string" ]
        )
        false
      end
    end
  end
end
