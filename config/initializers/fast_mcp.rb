# frozen_string_literal: true

require "fast_mcp"

# Custom transport that resolves project from API key token
class ProjectAuthTransport < FastMcp::Transports::AuthenticatedRackTransport
  RATE_LIMIT = 60
  RATE_PERIOD = 1.minute

  private

  def valid_token?(token)
    return false if token.blank?

    api_key = ApiKey.active.find_by_token(token)
    return false unless api_key

    if rate_limited?(api_key)
      raise RateLimitedError
    end

    api_key.touch_last_used!
    Current.mcp_project = api_key.project
    Current.mcp_api_key = api_key
    true
  end

  def rate_limited?(api_key)
    cache_key = "mcp_rate_limit/#{api_key.id}"
    Rails.cache.write(cache_key, 0, expires_in: RATE_PERIOD, unless_exist: true)
    count = Rails.cache.increment(cache_key, 1, expires_in: RATE_PERIOD) || 0
    count > RATE_LIMIT
  end

  def call(env)
    super
  rescue RateLimitedError
    [ 429, { "Content-Type" => "application/json", "Retry-After" => RATE_PERIOD.to_i.to_s },
      [ { error: "rate_limited", message: "Too many requests. Retry after #{RATE_PERIOD.to_i} seconds." }.to_json ] ]
  end

  class RateLimitedError < StandardError; end
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
    Dir[Rails.root.join("app/tools/**/*.rb")].each { |f| require f }
    tool_classes = ApplicationTool.descendants
    server.register_tools(*tool_classes) if tool_classes.any?
  end
end
