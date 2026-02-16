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
  end

  def validate_api_key(token)
    api_key = ApiKey.active.find_by_token(token)
    return false unless api_key

    raise RateLimitedError if rate_limited?(api_key)

    Current.mcp_project = api_key.project
    Current.mcp_api_key = api_key
    api_key.touch_last_used!
    true
  end

  def validate_oauth_token(token)
    access_token = Doorkeeper::AccessToken.by_token(token)
    return false unless access_token
    return false if access_token.expired? || access_token.revoked?

    project = Project.find_by(id: access_token.project_id)
    return false unless project

    Current.mcp_project = project
    Current.mcp_oauth_token = access_token
    true
  end

  def rate_limited?(api_key)
    cache_key = "mcp_rate_limit/#{api_key.id}"
    Rails.cache.write(cache_key, 0, expires_in: RATE_PERIOD, unless_exist: true)
    count = Rails.cache.increment(cache_key, 1)
    count > RATE_LIMIT
  end

  def unauthorized_response(request)
    body = JSON.generate(
      jsonrpc: "2.0",
      error: { code: -32_000, message: "Unauthorized: Valid API key or OAuth token required" },
      id: extract_request_id(request)
    )

    [ 401,
      {
        "Content-Type" => "application/json",
        "WWW-Authenticate" => "Bearer resource_metadata=\"/.well-known/oauth-protected-resource\""
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
    Rails.logger.warn("FastMcp AuthenticatedRackTransport not found in middleware stack; skipping swap")
  else
    raise
  end
end
