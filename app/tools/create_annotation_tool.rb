# frozen_string_literal: true

class CreateAnnotationTool < ApplicationTool
  tool_name "create_annotation"
  description "Create an annotation on a screenshot. Provide coordinates as percentages (0.0-100.0)."

  arguments do
    required(:project_id).filled(:integer).description("The project ID")
    required(:screenshot_id).filled(:integer).description("The screenshot ID to annotate")
    required(:x_percent).filled(:float).description("X position as percentage (0.0-100.0)")
    required(:y_percent).filled(:float).description("Y position as percentage (0.0-100.0)")
    required(:comment).filled(:string).description("The annotation comment text")
    optional(:width_percent).filled(:float).description("Region width as percentage (0.0-100.0)")
    optional(:height_percent).filled(:float).description("Region height as percentage (0.0-100.0)")
    optional(:viewport).filled(:string).description("Viewport the annotation applies to: desktop, tablet, or mobile (default: desktop)")
  end

  def call(project_id:, screenshot_id:, x_percent:, y_percent:, comment:, width_percent: nil, height_percent: nil, viewport: "desktop")
    error = require_project(project_id)
    return error if error

    unless ScreenshotImage.viewports.key?(viewport)
      return { error: "invalid_arguments", message: "viewport must be one of #{ScreenshotImage.viewports.keys.join(', ')}" }.to_json
    end

    with_error_handling do
      screenshot = current_project.screenshots.find(screenshot_id)

      # Guard: the annotation's viewport must correspond to an existing
      # ScreenshotImage on this screenshot. Otherwise annotation.crop returns
      # nil forever and the pin has nowhere to render.
      unless screenshot.screenshot_images.exists?(viewport: viewport)
        available = screenshot.available_viewports
        return { error: "invalid_arguments",
                 message: "Screenshot has no #{viewport} variant. Available: #{available.join(', ').presence || 'none'}" }.to_json
      end

      annotation = screenshot.annotations.create!(
        user: current_user,
        x_percent: x_percent,
        y_percent: y_percent,
        width_percent: width_percent,
        height_percent: height_percent,
        comment: comment,
        viewport: viewport
      )

      { annotation: serialize_annotation(annotation) }.to_json
    end
  end
end
