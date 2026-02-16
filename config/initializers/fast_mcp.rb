# frozen_string_literal: true

require "fast_mcp"

# Custom transport that authenticates via API key token or OAuth 2.1 bearer
# token, resolves the current project, and enforces per-key rate limiting
# (60 req/min).
class ProjectAuthTransport < FastMcp::Transports::AuthenticatedRackTransport
  RATE_LIMIT = 60
  RATE_PERIOD = 1.minute

  # NOTE: Raises RateLimitedError instead of returning false for rate-limited
  # requests, so call() can produce a proper HTTP 429 response rather than
  # a generic 401 authentication failure.
  def call(env)
    super
  rescue RateLimitedError
    [ 429, { "Content-Type" => "application/json", "Retry-After" => RATE_PERIOD.to_i.to_s },
      [ { error: "rate_limited", message: "Too many requests. Retry after #{RATE_PERIOD.to_i} seconds." }.to_json ] ]
  end

  # FastMcp 1.6.0 broadcasts responses via SSE only, returning an empty HTTP
  # body for Streamable HTTP POSTs. Override send_message so the JSON-RPC
  # result propagates back as the Rack response body.
  def send_message(message)
    json = message.is_a?(String) ? message : JSON.generate(message)
    super(json)
    [ json ]
  end

  def handle_internal_error(error)
    logger.error("MCP internal error: #{error.message}")
    Honeybadger.notify(error)
    json_rpc_error_response(500, -32_603, "Internal error")
  end

  private

  def valid_token?(token)
    return false if token.blank?

    if token.start_with?("sk_proj_")
      validate_api_key(token)
    else
      validate_oauth_token(token)
    end
  rescue RateLimitedError
    raise
  rescue StandardError => e
    Rails.logger.error("Token validation error: #{e.class}: #{e.message}")
    Honeybadger.notify(e, context: { token_prefix: token&.first(8) })
    false
  end

  def validate_api_key(token)
    api_key = ApiKey.active.find_by_token(token)
    unless api_key
      Rails.logger.info("MCP auth: API key not found")
      return false
    end

    raise RateLimitedError if rate_limited?(api_key)

    project = api_key.project
    unless project
      Rails.logger.error("MCP auth: API key #{api_key.id} references missing project")
      Honeybadger.notify("API key references deleted project", context: { api_key_id: api_key.id })
      return false
    end

    Current.mcp_user = project.creator
    Current.mcp_project = project
    Current.mcp_api_key = api_key

    begin
      api_key.touch_last_used!
    rescue ActiveRecord::ActiveRecordError => e
      Rails.logger.warn("Failed to update last_used_at for API key #{api_key.id}: #{e.message}")
    end

    true
  end

  def validate_oauth_token(token)
    access_token = Doorkeeper::AccessToken.by_token(token)
    unless access_token
      Rails.logger.info("MCP auth: OAuth token not found")
      return false
    end

    if access_token.revoked?
      Rails.logger.info("MCP auth: OAuth token revoked (id=#{access_token.id})")
      return false
    end

    if access_token.expired?
      Rails.logger.info("MCP auth: OAuth token expired (id=#{access_token.id})")
      return false
    end

    raise RateLimitedError if rate_limited_oauth?(access_token)

    user = User.find_by(id: access_token.resource_owner_id)
    unless user
      Rails.logger.error("MCP auth: OAuth token #{access_token.id} references missing user (resource_owner_id=#{access_token.resource_owner_id})")
      Honeybadger.notify("OAuth token references deleted user", context: { token_id: access_token.id, resource_owner_id: access_token.resource_owner_id })
      return false
    end

    Current.mcp_user = user
    Current.mcp_oauth_token = access_token
    true
  end

  def rate_limited?(api_key)
    cache_key = "mcp_rate_limit/#{api_key.id}"
    Rails.cache.write(cache_key, 0, expires_in: RATE_PERIOD, unless_exist: true)
    count = Rails.cache.increment(cache_key, 1)
    count.present? && count > RATE_LIMIT
  rescue StandardError => e
    Rails.logger.error("Rate limiting check failed: #{e.class}: #{e.message}")
    Honeybadger.notify(e, context: { api_key_id: api_key.id })
    false
  end

  def rate_limited_oauth?(access_token)
    cache_key = "mcp_rate_limit/oauth/#{access_token.id}"
    Rails.cache.write(cache_key, 0, expires_in: RATE_PERIOD, unless_exist: true)
    count = Rails.cache.increment(cache_key, 1)
    count.present? && count > RATE_LIMIT
  rescue StandardError => e
    Rails.logger.error("Rate limiting check failed: #{e.class}: #{e.message}")
    Honeybadger.notify(e, context: { token_id: access_token.id })
    false
  end

  def unauthorized_response(request)
    rack_request = request.is_a?(Hash) ? Rack::Request.new(request) : request
    base_url = "#{rack_request.scheme}://#{rack_request.host_with_port}"

    body = JSON.generate(
      jsonrpc: "2.0",
      error: { code: -32_000, message: "Unauthorized: Valid API key or OAuth token required" },
      id: extract_request_id(request)
    )

    [ 401,
      {
        "Content-Type" => "application/json",
        "WWW-Authenticate" => "Bearer resource_metadata=\"#{base_url}/.well-known/oauth-protected-resource\", scope=\"mcp_read mcp_write\""
      },
      [ body ] ]
  end

  class RateLimitedError < StandardError; end
end

FastMcp.mount_in_rails(
  Rails.application,
  name: "screenote",
  version: "1.0.0",
  path_prefix: "/mcp",
  authenticate: true,
  # FastMcp requires a non-nil token to enable auth. ProjectAuthTransport
  # overrides valid_token? to validate against the database instead.
  auth_token: SecureRandom.hex(32),
  localhost_only: false
) do |server|
  Rails.application.config.after_initialize do
    Dir[Rails.root.join("app/tools/**/*.rb")].each { |f| require f }
    tool_classes = ApplicationTool.descendants
    server.register_tools(*tool_classes) if tool_classes.any?
  end
end

# FastMcp.mount_in_rails ignores the transport: option and always inserts
# AuthenticatedRackTransport. Swap it with our custom transport so that
# API key tokens are looked up in the database instead of compared to a
# static string.
begin
  Rails.application.config.middleware.swap(
    FastMcp::Transports::AuthenticatedRackTransport,
    ProjectAuthTransport,
    FastMcp.server,
    path_prefix: "/mcp",
    messages_route: "messages",
    sse_route: "sse",
    # FastMcp requires a non-nil token to enable auth. ProjectAuthTransport
    # overrides valid_token? to validate against the database instead.
    auth_token: SecureRandom.hex(32),
    localhost_only: false,
    logger: Rails.logger,
    allowed_origins: FastMcp.default_rails_allowed_origins(Rails.application),
    allowed_ips: FastMcp::Transports::RackTransport::DEFAULT_ALLOWED_IPS
  )
rescue RuntimeError => e
  if e.message.include?("No such middleware")
    Rails.logger.error("CRITICAL: FastMcp ProjectAuthTransport middleware swap failed — MCP auth is broken")
    Honeybadger.notify("FastMcp middleware swap failed - MCP auth broken", context: { error: e.message })
  else
    raise
  end
end
