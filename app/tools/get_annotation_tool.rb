# frozen_string_literal: true

class GetAnnotationTool < ApplicationTool
  tool_name "get_annotation"
  description "Get annotation details with a cropped image of the annotated region (base64-encoded PNG)."

  arguments do
    required(:project_id).filled(:integer).description("The project ID")
    required(:annotation_id).filled(:integer).description("The annotation ID")
  end

  def call(project_id:, annotation_id:)
    error = require_project(project_id)
    return error if error

    with_error_handling do
      annotation = project_annotations(current_project).find(annotation_id)

      screenshot = annotation.screenshot
      cropped_base64 = begin
        annotation.crop
      rescue => e
        Screenote::Monitoring.notify(e, context: {
          annotation_id: annotation.id,
          screenshot_id: screenshot.id,
          viewport: annotation.viewport
        })
        nil
      end

      comments = annotation.annotation_comments.includes(:user, :api_key).order(:created_at).map do |ac|
        {
          id: ac.id,
          action: ac.action,
          body: ac.body,
          author: ac.user&.email || ac.api_key&.name || "Unknown",
          created_at: ac.created_at.iso8601
        }
      end

      serialize_annotation(annotation).merge(
        screenshot_status: screenshot.status,
        cropped_image_base64: cropped_base64,
        mime_type: "image/png",
        comments: comments
      ).to_json
    end
  end
end
