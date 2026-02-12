# frozen_string_literal: true

class ApplicationTool < FastMcp::Tool
  private

  def current_project
    Thread.current[:mcp_current_project]
  end

  def current_api_key
    Thread.current[:mcp_current_api_key]
  end
end
