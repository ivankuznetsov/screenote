# frozen_string_literal: true

class GetAnnotationTool < ApplicationTool
  tool_name "get_annotation"
  description "Get annotation details with a cropped image of the annotated region (base64-encoded PNG), " \
    "plus the images attached to the annotation and to each of its comments: alt text, media type, " \
    "dimensions, size, and a short-lived URL that must be fetched with the same bearer credential."
  mcp_action scope: :mcp_read, read_only: true, destructive: false, idempotent: true, open_world: false

  arguments do
    required(:project_id).filled(:integer).description("The project ID")
    required(:annotation_id).filled(:integer).description("The annotation ID")
  end

  def call(project_id:, annotation_id:)
    error = require_project(project_id)
    return error if error

    with_error_handling do
      annotation = project_annotation_details(current_project).find(annotation_id)

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

      # REST is canonical for the attachment object, but the shipped MCP
      # envelope keeps every key it already had, in the same place.
      Api::V1::ContractSerializer.annotation_detail(
        annotation,
        cropped_base64: cropped_base64,
        url_options: Screenote::Deployment.current.url_options
      ).to_json
    end
  end
end
