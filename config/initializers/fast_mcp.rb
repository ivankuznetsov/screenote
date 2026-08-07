# frozen_string_literal: true

require "fast_mcp"

module Screenote
  # FastMCP 1.6 logs complete requests and responses. Keep dependency logs
  # operationally useful without allowing bearer-authenticated payloads,
  # tool results, or backtraces into application logs.
  class McpSanitizingLogger
    def initialize(delegate)
      @delegate = delegate
    end

    def debug(*)
      nil
    end

    def info(*)
      nil
    end

    def warn(*)
      delegate.warn("MCP transport warning")
    end

    def error(*)
      delegate.error("MCP transport error")
    end

    private

    attr_reader :delegate
  end

  # FastMCP 1.6 includes absolute backtraces when a parsed JSON value is not
  # an object, and when an uncaught tool error reaches the server. Normalize
  # those dependency-generated errors at the application boundary.
  module McpServerGuard
    private

    def send_error(code, message, id = nil)
      message = "Invalid Request" if code == -32_600 && message.to_s.start_with?("Internal error:")
      super(code, message, id)
    end

    def send_error_result(message, id)
      message = "Tool execution failed" if message.to_s.match?(%r{/[^[:space:]]+\.rb:\d+})
      super(message, id)
    end
  end
end

FastMcp::Server.prepend(Screenote::McpServerGuard) unless FastMcp::Server < Screenote::McpServerGuard

# Custom transport that authenticates via API key token or OAuth 2.1 bearer
# token, resolves the current project, and enforces per-key rate limiting
# (60 req/min).
class ProjectAuthTransport < FastMcp::Transports::AuthenticatedRackTransport
  RATE_LIMIT = 60
  RATE_PERIOD = 1.minute
  PRE_AUTH_RATE_LIMIT = 300
  RATE_LIMIT_STORE = Screenote::RateLimitStore.new

  # NOTE: Raises RateLimitedError instead of returning false for rate-limited
  # requests, so call() can produce a proper HTTP 429 response rather than
  # a generic 401 authentication failure.
  def call(env)
    Current.reset
    request = Rack::Request.new(env)
    return super(env) unless request.path.start_with?(path_prefix)
    return endpoint_not_found_response unless streamable_http_path?(request.path)
    return method_not_allowed_response unless request.post?
    return forbidden_response("Forbidden: Remote IP not allowed") unless valid_client_ip?(request)
    return forbidden_response("Forbidden: Origin validation failed") unless validate_origin(request, env)

    raise RateLimitedError if pre_auth_rate_limited?(request.ip)

    super(streamable_http_env(env))
  rescue RateLimitedError
    [ 429, { "Content-Type" => "application/json", "Retry-After" => RATE_PERIOD.to_i.to_s },
      [ { error: "rate_limited", message: "Too many requests. Retry after #{RATE_PERIOD.to_i} seconds." }.to_json ] ]
  rescue Screenote::RateLimitStore::Unavailable
    [ 503, { "Content-Type" => "application/json", "Retry-After" => "60", "Cache-Control" => "no-store" },
      [ { error: "temporarily_unavailable", message: "Rate limiting is temporarily unavailable." }.to_json ] ]
  ensure
    Current.reset
  end

  # FastMcp 1.6.0 broadcasts every response to every registered SSE client.
  # Screenote supports request-bound Streamable HTTP only, so return the
  # response to the current Rack request without calling the broadcast path.
  def send_message(message)
    json = message.is_a?(String) ? message : JSON.generate(message)
    [ json ]
  end

  def handle_internal_error(error)
    logger.error("MCP internal error: #{error.message}")
    Screenote::Monitoring.notify(error)
    json_rpc_error_response(500, -32_603, "Internal error")
  end

  private

  def streamable_http_path?(request_path)
    [ path_prefix, "#{path_prefix}/" ].include?(request_path)
  end

  # FastMcp 1.6.0 internally dispatches JSON-RPC POSTs through its legacy
  # messages route. Rewrite only the canonical endpoint inside this middleware
  # so clients use POST /mcp while the public legacy route remains unavailable.
  def streamable_http_env(env)
    env.merge("PATH_INFO" => "#{path_prefix}/#{messages_route}")
  end

  def valid_token?(token)
    Current.authenticated_principal = nil
    return false if token.blank?

    principal = Api::BearerAuthenticator.call(token)
    unless principal
      Rails.logger.info("MCP auth: credential not found or inactive")
      return false
    end

    if principal.api_key?
      raise RateLimitedError if rate_limited?(principal.api_key)
    else
      raise RateLimitedError if rate_limited_oauth?(principal.oauth_token)
    end

    Current.authenticated_principal = principal
    true
  rescue RateLimitedError
    raise
  rescue Screenote::RateLimitStore::Unavailable
    raise
  rescue StandardError => e
    Rails.logger.error("Token validation error: #{e.class}: #{e.message}")
    Screenote::Monitoring.notify(e)
    false
  end

  def pre_auth_rate_limited?(ip_address)
    digest = Digest::SHA256.hexdigest(ip_address.to_s)
    cache_key = "mcp_rate_limit/ip/#{digest}"
    RATE_LIMIT_STORE.increment(cache_key, 1, expires_in: RATE_PERIOD) > PRE_AUTH_RATE_LIMIT
  end

  def rate_limited?(api_key)
    cache_key = "mcp_rate_limit/#{api_key.id}"
    RATE_LIMIT_STORE.increment(cache_key, 1, expires_in: RATE_PERIOD) > RATE_LIMIT
  end

  def rate_limited_oauth?(access_token)
    cache_key = "mcp_rate_limit/oauth/#{access_token.id}"
    RATE_LIMIT_STORE.increment(cache_key, 1, expires_in: RATE_PERIOD) > RATE_LIMIT
  end

  def unauthorized_response(request)
    base_url = Screenote::Deployment.current.base_url

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

module Screenote
  class McpToolRegistry
    TOOL_CLASS_NAMES = %w[
      AddAnnotationCommentTool
      CancelInvitationTool
      CreateAnnotationTool
      CreateMultiViewportScreenshotTool
      CreateProjectTool
      CreateScreenshotTool
      CreateScreenshotUploadTool
      CreateSnapshotTool
      GetAnnotationTool
      InviteCollaboratorTool
      ListAnnotationsTool
      ListPagesTool
      ListProjectMembersTool
      ListProjectsTool
      ListScreenshotsTool
      RemoveProjectMemberTool
      ReopenAnnotationTool
      ResolveAnnotationTool
    ].freeze

    class << self
      def tool_classes
        TOOL_CLASS_NAMES.map do |class_name|
          class_name.constantize.tap { |tool_class| validate!(tool_class) }
        end.freeze
      end

      private

      def validate!(tool_class)
        return if tool_class < ApplicationTool && tool_class.mcp_policy.present?

        raise "Refusing to register unclassified MCP tool #{tool_class.name}"
      end
    end
  end
end

mcp_logger = Screenote::McpSanitizingLogger.new(Rails.logger)

FastMcp.mount_in_rails(
  Rails.application,
  name: "screenote",
  version: "1.0.0",
  path_prefix: "/mcp",
  logger: mcp_logger,
  authenticate: true,
  # FastMcp requires a non-nil token to enable auth. ProjectAuthTransport
  # overrides valid_token? to validate against the database instead.
  auth_token: SecureRandom.hex(32),
  localhost_only: false
) do |server|
  Rails.application.config.after_initialize do
    tool_classes = Screenote::McpToolRegistry.tool_classes
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
    logger: mcp_logger,
    allowed_origins: FastMcp.default_rails_allowed_origins(Rails.application),
    allowed_ips: FastMcp::Transports::RackTransport::DEFAULT_ALLOWED_IPS
  )
rescue RuntimeError => e
  if e.message.include?("No such middleware")
    Rails.logger.error("CRITICAL: FastMcp ProjectAuthTransport middleware swap failed — MCP auth is broken")
    Screenote::Monitoring.notify("FastMcp middleware swap failed - MCP auth broken", context: { error: e.message })
  else
    raise
  end
end
