# frozen_string_literal: true

class CreateAnnotationTool < ApplicationTool
  tool_name "create_annotation"
  description "Create an annotation on a screenshot. Provide coordinates as percentages (0.0-100.0)."
  mcp_action scope: :mcp_write, read_only: false, destructive: false, idempotent: false, open_world: false

  arguments do
    required(:project_id).filled(:integer).description("The project ID")
    required(:screenshot_id).filled(:integer).description("The screenshot ID to annotate")
    required(:x_percent).filled(:float).description("X position as percentage (0.0-100.0)")
    required(:y_percent).filled(:float).description("Y position as percentage (0.0-100.0)")
    required(:comment).filled(:string).description("The annotation comment text")
    optional(:width_percent).filled(:float).description("Region width as percentage (0.0-100.0)")
    optional(:height_percent).filled(:float).description("Region height as percentage (0.0-100.0)")
    optional(:viewport).filled(:string).description("Viewport the annotation applies to: desktop, tablet, or mobile. Required when the screenshot has multiple variants.")
  end

  def call(project_id:, screenshot_id:, x_percent:, y_percent:, comment:, width_percent: nil, height_percent: nil, viewport: nil)
    error = require_project(project_id)
    return error if error

    if viewport && !ScreenshotImage.viewports.key?(viewport)
      return invalid("viewport must be one of #{ScreenshotImage.viewports.keys.join(', ')}")
    end

    with_error_handling do
      screenshot = current_project.screenshots.find(screenshot_id)
      available = screenshot.available_viewports

      # Multi-variant screenshots require explicit viewport so an agent can't
      # silently attach a mobile-layout annotation to desktop. Single-variant
      # screenshots default to that variant (preserves backward compat with
      # legacy screenshots uploaded before multi-viewport).
      if viewport.nil?
        return invalid("viewport is required for multi-variant screenshots. Available: #{available.join(', ')}") if available.size > 1
        viewport = available.first
      elsif !available.include?(viewport)
        return invalid("Screenshot has no #{viewport} variant. Available: #{available.join(', ').presence || 'none'}")
      end

      annotation = screenshot.annotations.create!(
        **current_actor_attributes,
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

  # Visibility marker: any helper methods added below default to private so
  # subclass authors don't silently expose internals.
  private
end
