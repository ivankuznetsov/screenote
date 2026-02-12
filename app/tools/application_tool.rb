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
end
