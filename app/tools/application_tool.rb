# frozen_string_literal: true

class ApplicationTool < FastMcp::Tool
  private

  def current_project
    Current.mcp_project
  end

  def current_user
    Current.mcp_user
  end

  # Resolves the project for the current request. API key auth pre-sets
  # Current.mcp_project; OAuth auth requires an explicit project_id.
  def resolve_project(project_id)
    return current_project if current_project

    unless project_id
      return nil
    end

    project = current_user.projects.find_by(id: project_id)
    return nil unless project

    Current.mcp_project = project
    project
  end

  def require_project(project_id)
    project = resolve_project(project_id)
    unless project
      if project_id && current_user
        return { error: "forbidden", message: "You don't have access to project #{project_id}" }.to_json
      else
        return { error: "missing_project_id", message: "project_id is required" }.to_json
      end
    end
    nil
  end

  def with_error_handling
    yield
  rescue ActiveRecord::RecordNotFound => e
    { error: "not_found", message: e.message }.to_json
  rescue ActiveRecord::RecordInvalid => e
    { error: "validation_failed", message: e.message, details: e.record.errors.full_messages }.to_json
  rescue StandardError => e
    # Honeybadger.notify returns the notice id, or nil when the notifier is
    # disabled, filtered, or rate-limited — the `if correlation_id` guard
    # is real, not dead code.
    correlation_id = Honeybadger.notify(e)
    payload = { error: "internal_error", message: "An unexpected error occurred" }
    payload[:correlation_id] = correlation_id if correlation_id
    payload.to_json
  end

  # Shared structured response for argument-validation failures so every MCP
  # tool returns the same envelope to the agent.
  def invalid(message)
    { error: "invalid_arguments", message: message }.to_json
  end

  def project_annotations(project)
    Annotation.joins(screenshot: { page: :project })
      .where(projects: { id: project.id })
      .includes(:user, :screenshot, :annotation_comments)
  end

  def serialize_annotation(annotation)
    annotation.as_api_json
  end
end
