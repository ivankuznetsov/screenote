# frozen_string_literal: true

class GetAnnotationTool < ApplicationTool
  tool_name "get_annotation"
  description "Get annotation details with a cropped image of the annotated region (base64-encoded PNG)."

  arguments do
    required(:annotation_id).filled(:integer).description("The annotation ID")
  end

  def call(annotation_id:)
    with_error_handling do
      annotation = project_annotations.find(annotation_id)

      screenshot = annotation.screenshot
      cropped_base64 = nil
      if screenshot.ready? && screenshot.image.attached?
        begin
          cropped_base64 = AnnotationCropService.crop(screenshot, annotation)
        rescue => e
          Honeybadger.notify(e, context: { annotation_id: annotation.id, screenshot_id: screenshot.id })
        end
      end

      serialize_annotation(annotation).merge(
        screenshot_status: screenshot.status,
        cropped_image_base64: cropped_base64,
        mime_type: "image/png"
      ).to_json
    end
  end
end
