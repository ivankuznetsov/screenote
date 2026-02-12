# frozen_string_literal: true

class GetAnnotationTool < ApplicationTool
  tool_name "get_annotation"
  description "Get annotation details with a cropped image of the annotated region, optimized for AI vision."

  arguments do
    required(:annotation_id).filled(:integer).description("The annotation ID")
  end

  def call(annotation_id:)
    with_error_handling do
      annotation = Annotation.joins(screenshot: :project)
        .where(projects: { id: current_project.id })
        .includes(:user, :screenshot)
        .find(annotation_id)

      screenshot = annotation.screenshot
      cropped_base64 = if screenshot.ready? && screenshot.image.attached?
        AnnotationCropService.crop(screenshot, annotation)
      end

      {
        id: annotation.id,
        screenshot_id: annotation.screenshot_id,
        screenshot_status: screenshot.status,
        type: annotation.point? ? "point" : "region",
        coordinates: {
          x_percent: annotation.x_percent,
          y_percent: annotation.y_percent,
          width_percent: annotation.width_percent,
          height_percent: annotation.height_percent
        },
        comment: annotation.comment,
        status: annotation.status,
        author: annotation.user.email,
        cropped_image_base64: cropped_base64,
        mime_type: "image/png",
        created_at: annotation.created_at.iso8601
      }.to_json
    end
  end
end
