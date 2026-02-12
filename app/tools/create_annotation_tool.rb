# frozen_string_literal: true

class CreateAnnotationTool < ApplicationTool
  tool_name "create_annotation"
  description "Create an annotation on a screenshot. Provide coordinates as percentages (0.0-100.0)."

  arguments do
    required(:screenshot_id).filled(:integer).description("The screenshot ID to annotate")
    required(:x_percent).filled(:float).description("X position as percentage (0.0-100.0)")
    required(:y_percent).filled(:float).description("Y position as percentage (0.0-100.0)")
    required(:comment).filled(:string).description("The annotation comment text")
    optional(:width_percent).filled(:float).description("Region width as percentage (0.0-100.0)")
    optional(:height_percent).filled(:float).description("Region height as percentage (0.0-100.0)")
  end

  def call(screenshot_id:, x_percent:, y_percent:, comment:, width_percent: nil, height_percent: nil)
    with_error_handling do
      screenshot = current_project.screenshots.find(screenshot_id)

      annotation = screenshot.annotations.create!(
        user: current_project.creator,
        x_percent: x_percent,
        y_percent: y_percent,
        width_percent: width_percent,
        height_percent: height_percent,
        comment: comment
      )

      { annotation: serialize_annotation(annotation) }.to_json
    end
  end
end
