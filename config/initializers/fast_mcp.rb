# frozen_string_literal: true

require "fast_mcp"

# Custom transport that resolves project from API key token
class ProjectAuthTransport < FastMcp::Transports::AuthenticatedRackTransport
  private

  def valid_token?(token)
    return false if token.blank?

    api_key = ApiKey.active.find_by(token: token)
    return false unless api_key

    api_key.touch_last_used!
    Thread.current[:mcp_current_project] = api_key.project
    Thread.current[:mcp_current_api_key] = api_key
    true
  end
end

FastMcp.mount_in_rails(
  Rails.application,
  name: "screenote",
  version: "1.0.0",
  path_prefix: "/mcp",
  authenticate: true,
  auth_token: "ignored",
  transport: ProjectAuthTransport,
  localhost_only: false
) do |server|
  Rails.application.config.after_initialize do
    tool_classes = ApplicationTool.descendants rescue [] # rubocop:disable Style/RescueModifier
    server.register_tools(*tool_classes) if tool_classes.any?
  end
end
