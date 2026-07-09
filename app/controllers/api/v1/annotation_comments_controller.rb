# frozen_string_literal: true

module Api
  module V1
    class AnnotationCommentsController < Api::BaseController
      def create
        return unless require_scope!("mcp_write")

        project = require_current_project!(params[:project_id])
        return unless project

        annotation = Api::V1::ProjectScope.annotations(project).find(params[:annotation_id])
        comment = annotation.annotation_comments.create!(
          api_key: current_api_key,
          user: current_user,
          body: params[:body],
          action: :comment
        )

        render json: {
          success: true,
          comment: Api::V1::ContractSerializer.annotation_comment(comment, annotation: annotation)
        }, status: :created
      end
    end
  end
end
