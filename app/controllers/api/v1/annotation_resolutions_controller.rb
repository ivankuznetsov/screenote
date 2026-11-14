# frozen_string_literal: true

module Api
  module V1
    class AnnotationResolutionsController < Api::BaseController
      def create
        return unless require_scope!(AuthenticatedPrincipal::WRITE_SCOPE)

        project = require_current_project!(params[:project_id])
        return unless project

        annotation = Api::V1::ProjectScope.annotations(project).find(params[:annotation_id])
        comment_body = scalar_param(:comment)
        return if performed?

        operation, comment = annotation.resolve_idempotently!(
          user: current_user,
          api_key: current_api_key,
          body: comment_body.presence || "Marked as resolved"
        )

        render json: {
          success: true,
          operation: operation,
          annotation: Api::V1::ContractSerializer.annotation(annotation.reload),
          comment: comment && Api::V1::ContractSerializer.annotation_comment(comment, annotation: annotation)
        }
      end
    end
  end
end
