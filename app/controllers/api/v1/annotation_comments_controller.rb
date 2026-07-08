# frozen_string_literal: true

module Api
  module V1
    class AnnotationCommentsController < Api::BaseController
      def create
        annotation = Api::V1::ProjectScope.annotations(current_project).find(params[:annotation_id])
        comment = annotation.annotation_comments.create!(
          api_key: current_api_key,
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
