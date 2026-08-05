# frozen_string_literal: true

require "test_helper"

class McpAuthTest < ActiveSupport::TestCase
  ALICE_TOKEN = "sk_proj_test_alice_key_000000000000000000000000"
  BOB_TOKEN = "sk_proj_test_bob_key_0000000000000000000000000"
  REVOKED_TOKEN = "sk_proj_test_alice_revoked_00000000000000000000"

  class BoundProjectTool < ApplicationTool
    tool_name "bound_project"
    description "Return the project bound to this request"
    mcp_action scope: :mcp_read, read_only: true, destructive: false, idempotent: true, open_world: false

    arguments do
    end

    def call
      { project_id: current_project.id }.to_json
    end
  end

  class SensitiveEchoTool < ApplicationTool
    tool_name "sensitive_echo"
    description "Echo a test-only sensitive value"
    mcp_action scope: :mcp_read, read_only: true, destructive: false, idempotent: true, open_world: false

    arguments do
      required(:text).filled(:string)
    end

    def call(text:)
      { echo: text }.to_json
    end
  end

  setup do
    @api_key = api_keys(:alice_key)
    @revoked_key = api_keys(:alice_key_revoked)
    @project = projects(:alice_project)
    @user = users(:alice)
    @original_cache = Rails.cache
    Rails.cache = ActiveSupport::Cache::MemoryStore.new
  end

  teardown do
    Current.reset
    Rails.cache = @original_cache
  end

  # --- API key auth tests ---

  test "valid_token? accepts active API key" do
    transport = build_transport
    result = transport.send(:valid_token?, ALICE_TOKEN)

    assert result, "Should accept valid active token"
    principal = Current.authenticated_principal
    assert_equal @api_key.project, principal.project
    assert_equal @api_key, principal.api_key
    assert_nil principal.user, "API key requests must not impersonate the key issuer"
    assert_equal @api_key.issued_by_user, principal.issuer
  end

  test "valid_token? rejects revoked API key" do
    transport = build_transport
    result = transport.send(:valid_token?, REVOKED_TOKEN)

    assert_not result, "Should reject revoked token"
    assert_nil Current.authenticated_principal
  end

  test "valid_token? rejects blank token" do
    transport = build_transport
    assert_not transport.send(:valid_token?, ""), "Should reject blank token"
    assert_not transport.send(:valid_token?, nil), "Should reject nil token"
  end

  test "valid_token? rejects unknown token" do
    transport = build_transport
    result = transport.send(:valid_token?, "sk_proj_nonexistent_token")

    assert_not result, "Should reject unknown token"
  end

  test "valid_token? touches last_used_at" do
    transport = build_transport
    old_time = @api_key.last_used_at

    transport.send(:valid_token?, ALICE_TOKEN)

    assert @api_key.reload.last_used_at > old_time, "Should update last_used_at"
  end

  # --- OAuth token auth tests ---

  test "valid_token? accepts valid OAuth access token" do
    app = create_oauth_application
    access_token = create_oauth_token(application: app, user: @user, project: @project)

    transport = build_transport
    result = transport.send(:valid_token?, access_token.token)

    assert result, "Should accept valid OAuth token"
    principal = Current.authenticated_principal
    assert_equal @user, principal.user, "Should preserve the OAuth resource owner"
    assert_equal access_token, principal.oauth_token
    assert_nil principal.api_key, "OAuth path must not set an API key"
    assert_equal @project, principal.project, "Project OAuth tokens must remain project-bound"
  end

  test "valid_token? rejects expired OAuth access token" do
    app = create_oauth_application
    access_token = create_oauth_token(application: app, user: @user, project: @project, expires_in: -1)

    transport = build_transport
    result = transport.send(:valid_token?, access_token.token)

    assert_not result, "Should reject expired OAuth token"
  end

  test "valid_token? rejects revoked OAuth access token" do
    app = create_oauth_application
    access_token = create_oauth_token(application: app, user: @user, project: @project, revoked_at: Time.current)

    transport = build_transport
    result = transport.send(:valid_token?, access_token.token)

    assert_not result, "Should reject revoked OAuth token"
  end

  test "valid_token? accepts OAuth token without project (user-scoped)" do
    app = create_oauth_application
    access_token = create_oauth_token(application: app, user: @user, project: nil)

    transport = build_transport
    result = transport.send(:valid_token?, access_token.token)

    assert result, "Should accept OAuth token without project (user-scoped auth)"
    assert_equal @user, Current.authenticated_principal.user
    assert_nil Current.authenticated_principal.project, "Should not set project for user-scoped token"
  end

  test "valid_token? routes sk_proj_ tokens to API key validation" do
    transport = build_transport
    transport.send(:valid_token?, ALICE_TOKEN)

    assert_equal @api_key, Current.authenticated_principal.api_key, "sk_proj_ prefix should use API key path"
    assert_nil Current.authenticated_principal.oauth_token
  end

  # --- Rate limiting tests ---

  test "rate_limited? returns false under limit" do
    transport = build_transport
    assert_not transport.send(:rate_limited?, @api_key), "Should not be rate limited on first request"
  end

  test "rate_limited? returns true when limit exceeded" do
    transport = build_transport
    cache_key = "mcp_rate_limit/#{@api_key.id}"

    Rails.cache.write(cache_key, ProjectAuthTransport::RATE_LIMIT, expires_in: 1.minute)

    assert transport.send(:rate_limited?, @api_key), "Should be rate limited after exceeding limit"
  end

  test "valid_token? raises RateLimitedError when rate limited" do
    transport = build_transport
    cache_key = "mcp_rate_limit/#{@api_key.id}"

    Rails.cache.write(cache_key, ProjectAuthTransport::RATE_LIMIT, expires_in: 1.minute)

    assert_raises(ProjectAuthTransport::RateLimitedError) do
      transport.send(:valid_token?, ALICE_TOKEN)
    end
  end

  test "RateLimitedError rescue produces 429 response" do
    response = begin
      raise ProjectAuthTransport::RateLimitedError
    rescue ProjectAuthTransport::RateLimitedError
      [ 429, { "Content-Type" => "application/json", "Retry-After" => ProjectAuthTransport::RATE_PERIOD.to_i.to_s },
        [ { error: "rate_limited", message: "Too many requests." }.to_json ] ]
    end

    assert_equal 429, response[0], "Should return 429 status"
    assert_equal "60", response[1]["Retry-After"], "Should include Retry-After header"
  end

  test "unauthorized challenge uses the canonical origin rather than request host" do
    transport = build_transport
    response = transport.send(
      :unauthorized_response,
      Rack::Request.new(Rack::MockRequest.env_for("http://attacker.example.test/mcp"))
    )

    assert_equal 401, response.first
    assert_includes response.second.fetch("WWW-Authenticate"),
      "#{Screenote::Deployment.current.base_url}/.well-known/oauth-protected-resource"
    assert_not_includes response.second.fetch("WWW-Authenticate"), "attacker.example.test"
  end

  test "OAuth tokens are rate limited" do
    app = create_oauth_application
    access_token = create_oauth_token(application: app, user: @user, project: @project)

    transport = build_transport
    cache_key = "mcp_rate_limit/oauth/#{access_token.id}"
    Rails.cache.write(cache_key, ProjectAuthTransport::RATE_LIMIT, expires_in: 1.minute)

    assert_raises(ProjectAuthTransport::RateLimitedError) do
      transport.send(:valid_token?, access_token.token)
    end
  end

  test "rate limiter backend failure is unavailable rather than permissive" do
    unavailable_store = Object.new
    unavailable_store.define_singleton_method(:increment) { |*, **| raise "cache offline" }
    Rails.cache = unavailable_store

    transport = build_transport
    assert_raises(Screenote::RateLimitStore::Unavailable) do
      transport.send(:valid_token?, ALICE_TOKEN)
    end

    assert_nil Current.authenticated_principal
  end

  test "streamable HTTP responses stay bound to each project principal" do
    transport = build_rack_transport
    alice_response = call_mcp(transport, token: ALICE_TOKEN, id: "alice")
    bob_response = call_mcp(transport, token: BOB_TOKEN, id: "bob")

    assert_equal 200, alice_response.fetch(:status)
    assert_equal "alice", alice_response.dig(:json, "id")
    assert_equal @project.id, tool_payload(alice_response).fetch("project_id")

    assert_equal 200, bob_response.fetch(:status)
    assert_equal "bob", bob_response.dig(:json, "id")
    assert_equal projects(:bob_project).id, tool_payload(bob_response).fetch("project_id")
    assert_nil Current.authenticated_principal
  end

  test "responses are never broadcast to a previously registered SSE client" do
    transport = build_rack_transport
    stale_stream = StringIO.new
    transport.register_sse_client("revoked-client", stale_stream)

    revoked_response = call_mcp(transport, token: REVOKED_TOKEN, id: "revoked")
    valid_response = call_mcp(transport, token: BOB_TOKEN, id: "valid")

    assert_equal 401, revoked_response.fetch(:status)
    assert_equal 200, valid_response.fetch(:status)
    assert_empty stale_stream.string,
      "A stale or revoked SSE stream must not receive another principal's JSON-RPC response"
  end

  test "legacy SSE and messages endpoints are unavailable" do
    transport = build_rack_transport

    sse_response = call_mcp(transport, token: ALICE_TOKEN, id: "sse", path: "/mcp/sse", method: "GET")
    messages_response = call_mcp(transport, token: ALICE_TOKEN, id: "messages", path: "/mcp/messages")

    assert_equal 404, sse_response.fetch(:status)
    assert_equal(-32_601, sse_response.dig(:json, "error", "code"))
    assert_equal 404, messages_response.fetch(:status)
    assert_equal(-32_601, messages_response.dig(:json, "error", "code"))
  end

  test "IP rate limiting rejects work before bearer authentication" do
    remote_address = "203.0.113.42"
    digest = Digest::SHA256.hexdigest(remote_address)
    Rails.cache.write(
      "mcp_rate_limit/ip/#{digest}",
      ProjectAuthTransport::PRE_AUTH_RATE_LIMIT,
      expires_in: 1.minute
    )

    response = assert_no_queries do
      call_mcp(
        build_rack_transport,
        token: ALICE_TOKEN,
        id: "pre-auth-limit",
        remote_address: remote_address
      )
    end

    assert_equal 429, response.fetch(:status)
    assert_equal "rate_limited", response.dig(:json, "error")
  end

  test "IP rate limiter failure is unavailable before bearer authentication" do
    unavailable_store = Object.new
    unavailable_store.define_singleton_method(:increment) { |*, **| raise "cache offline" }
    Rails.cache = unavailable_store

    response = call_mcp(build_rack_transport, token: ALICE_TOKEN, id: "pre-auth-unavailable")

    assert_equal 503, response.fetch(:status)
    assert_equal "no-store", response.dig(:headers, "Cache-Control")
    assert_equal "temporarily_unavailable", response.dig(:json, "error")
  end

  test "rejected origins paths and methods do not consume the pre-auth IP bucket" do
    remote_address = "203.0.113.43"
    logger = Screenote::McpSanitizingLogger.new(ActiveSupport::Logger.new(StringIO.new))
    transport = build_rack_transport(logger: logger, allowed_origins: [ "screenote.test" ])

    responses = assert_no_queries do
      cross_origin = 300.times.map do
        call_mcp(
          transport,
          token: "invalid-bearer",
          id: "cross-origin",
          host: "screenote.test",
          origin: "https://attacker.test",
          remote_address: remote_address
        )
      end
      noncanonical = 300.times.map do
        call_mcp(
          transport,
          token: "invalid-bearer",
          id: "noncanonical",
          path: "/mcp/messages",
          host: "screenote.test",
          origin: "https://screenote.test",
          remote_address: remote_address
        )
      end
      invalid_method = 300.times.map do
        call_mcp(
          transport,
          token: "invalid-bearer",
          id: "invalid-method",
          method: "GET",
          host: "screenote.test",
          origin: "https://screenote.test",
          remote_address: remote_address
        )
      end

      [ cross_origin.last, noncanonical.last, invalid_method.last ]
    end

    assert_equal [ 403, 404, 405 ], responses.map { |response| response.fetch(:status) }
    assert_nil Rails.cache.read(pre_auth_cache_key(remote_address))

    invalid_bearer = assert_queries_match(/(?:api_keys|oauth_access_tokens)/, count: 2) do
      call_mcp(
        transport,
        token: "invalid-bearer",
        id: "valid-shape",
        host: "screenote.test",
        origin: "https://screenote.test",
        remote_address: remote_address
      )
    end
    assert_equal 401, invalid_bearer.fetch(:status)
    assert_equal 1, Rails.cache.read(pre_auth_cache_key(remote_address))

    Rails.cache.write(
      pre_auth_cache_key(remote_address),
      ProjectAuthTransport::PRE_AUTH_RATE_LIMIT,
      expires_in: 1.minute
    )
    limited = assert_no_queries do
      call_mcp(
        transport,
        token: "invalid-bearer",
        id: "limited-before-lookup",
        host: "screenote.test",
        origin: "https://screenote.test",
        remote_address: remote_address
      )
    end
    assert_equal 429, limited.fetch(:status)
  end

  test "FastMCP logs omit normal request and result payloads" do
    log_output = StringIO.new
    logger = Screenote::McpSanitizingLogger.new(ActiveSupport::Logger.new(log_output))
    transport = build_rack_transport(logger: logger)
    sentinel = "private-comment-#{SecureRandom.hex(8)}"

    response = call_mcp(
      transport,
      token: ALICE_TOKEN,
      id: "private-payload",
      tool_name: "sensitive_echo",
      arguments: { text: sentinel }
    )

    assert_equal 200, response.fetch(:status)
    assert_equal sentinel, tool_payload(response).fetch("echo")
    assert_not_includes log_output.string, sentinel
    assert_not_includes log_output.string, ALICE_TOKEN
  end

  test "mounted FastMCP server uses the sanitizing logger" do
    assert_instance_of Screenote::McpSanitizingLogger, FastMcp.server.logger
  end

  test "authenticated non-object JSON has a generic response and sanitized logs" do
    log_output = StringIO.new
    logger = Screenote::McpSanitizingLogger.new(ActiveSupport::Logger.new(log_output))
    transport = build_rack_transport(logger: logger)
    sentinel = "private-array-value-#{SecureRandom.hex(8)}"

    response = call_mcp(
      transport,
      token: ALICE_TOKEN,
      id: "unused",
      raw_body: [ sentinel ].to_json
    )

    assert_equal 200, response.fetch(:status)
    assert_equal(-32_600, response.dig(:json, "error", "code"))
    assert_equal "Invalid Request", response.dig(:json, "error", "message")
    assert_not_includes response.fetch(:raw), sentinel
    assert_no_match(%r{/[^[:space:]]+\.rb:\d+}, response.fetch(:raw))
    assert_not_includes log_output.string, sentinel
    assert_no_match(%r{/[^[:space:]]+\.rb:\d+}, log_output.string)
  end

  private

  def build_transport
    ProjectAuthTransport.allocate
  end

  def build_rack_transport(logger: Rails.logger, allowed_origins: [])
    server = FastMcp::Server.new(name: "transport-security-test", version: "1", logger: logger)
    server.register_tools(BoundProjectTool, SensitiveEchoTool)
    ProjectAuthTransport.new(
      ->(_environment) { [ 404, { "Content-Type" => "text/plain" }, [ "not found" ] ] },
      server,
      path_prefix: "/mcp",
      messages_route: "messages",
      sse_route: "sse",
      auth_token: "unused",
      localhost_only: false,
      allowed_origins: allowed_origins,
      logger: logger
    )
  end

  def call_mcp(
    transport,
    token:,
    id:,
    path: "/mcp",
    method: "POST",
    remote_address: "127.0.0.1",
    host: "localhost",
    origin: nil,
    tool_name: "bound_project",
    arguments: {},
    raw_body: nil
  )
    body = raw_body || {
      jsonrpc: "2.0",
      id: id,
      method: "tools/call",
      params: { name: tool_name, arguments: arguments }
    }.to_json
    request_options = {
      method: method,
      input: body,
      "CONTENT_TYPE" => "application/json",
      "HTTP_AUTHORIZATION" => "Bearer #{token}",
      "REMOTE_ADDR" => remote_address
    }
    request_options["HTTP_ORIGIN"] = origin if origin
    environment = Rack::MockRequest.env_for("http://#{host}#{path}", request_options)
    status, headers, response_body = transport.call(environment)
    raw_body = response_body.each.to_a.join

    {
      status: status,
      headers: headers,
      raw: raw_body,
      json: raw_body.present? ? JSON.parse(raw_body) : nil
    }
  end

  def pre_auth_cache_key(remote_address)
    digest = Digest::SHA256.hexdigest(remote_address)
    "mcp_rate_limit/ip/#{digest}"
  end

  def tool_payload(response)
    JSON.parse(response.dig(:json, "result", "content", 0, "text"))
  end
end
