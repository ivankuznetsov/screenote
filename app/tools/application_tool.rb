# frozen_string_literal: true

class ApplicationTool < FastMcp::Tool
  private

  def current_project
    Current.mcp_project
  end

  def current_api_key
    Current.mcp_api_key
  end

  def with_error_handling
    yield
  rescue ActiveRecord::RecordNotFound => e
    { error: "not_found", message: e.message }.to_json
  rescue ActiveRecord::RecordInvalid => e
    { error: "validation_failed", message: e.message, details: e.record.errors.full_messages }.to_json
  end

  def project_annotations
    Annotation.joins(screenshot: :project)
      .where(projects: { id: current_project.id })
      .includes(:user, :screenshot)
  end

  def serialize_annotation(annotation)
    {
      id: annotation.id,
      screenshot_id: annotation.screenshot_id,
      type: annotation.point? ? "point" : "region",
      coordinates: {
        x_percent: annotation.x_percent,
        y_percent: annotation.y_percent,
        width_percent: annotation.width_percent,
        height_percent: annotation.height_percent
      },
      comment: annotation.comment,
      status: annotation.status,
      author: annotation.user&.email,
      created_at: annotation.created_at.iso8601
    }
  end
end
