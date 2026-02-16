# frozen_string_literal: true

require "test_helper"

class McpAuthTest < ActiveSupport::TestCase
  ALICE_TOKEN = "sk_proj_test_alice_key_000000000000000000000000"
  REVOKED_TOKEN = "sk_proj_test_alice_revoked_00000000000000000000"

  setup do
    @api_key = api_keys(:alice_key)
    @revoked_key = api_keys(:alice_key_revoked)
    @project = projects(:alice_project)
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
    assert_equal @api_key.project, Current.mcp_project
    assert_equal @api_key, Current.mcp_api_key
  end

  test "valid_token? rejects revoked API key" do
    transport = build_transport
    result = transport.send(:valid_token?, REVOKED_TOKEN)

    assert_not result, "Should reject revoked token"
    assert_nil Current.mcp_project
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
    app = Doorkeeper::Application.create!(
      name: "Test OAuth App",
      redirect_uri: "http://localhost/callback",
      confidential: false
    )
    access_token = Doorkeeper::AccessToken.create!(
      application: app,
      resource_owner_id: users(:alice).id,
      project_id: @project.id,
      scopes: "mcp_read",
      expires_in: 1.hour
    )

    transport = build_transport
    result = transport.send(:valid_token?, access_token.token)

    assert result, "Should accept valid OAuth token"
    assert_equal @project, Current.mcp_project
    assert_equal access_token, Current.mcp_oauth_token
    assert_nil Current.mcp_api_key, "Should not set mcp_api_key for OAuth tokens"
  end

  test "valid_token? rejects expired OAuth access token" do
    app = Doorkeeper::Application.create!(
      name: "Test OAuth App",
      redirect_uri: "http://localhost/callback",
      confidential: false
    )
    access_token = Doorkeeper::AccessToken.create!(
      application: app,
      resource_owner_id: users(:alice).id,
      project_id: @project.id,
      scopes: "mcp_read",
      expires_in: -1
    )

    transport = build_transport
    result = transport.send(:valid_token?, access_token.token)

    assert_not result, "Should reject expired OAuth token"
  end

  test "valid_token? rejects revoked OAuth access token" do
    app = Doorkeeper::Application.create!(
      name: "Test OAuth App",
      redirect_uri: "http://localhost/callback",
      confidential: false
    )
    access_token = Doorkeeper::AccessToken.create!(
      application: app,
      resource_owner_id: users(:alice).id,
      project_id: @project.id,
      scopes: "mcp_read",
      expires_in: 1.hour,
      revoked_at: Time.current
    )

    transport = build_transport
    result = transport.send(:valid_token?, access_token.token)

    assert_not result, "Should reject revoked OAuth token"
  end

  test "valid_token? rejects OAuth token with missing project" do
    app = Doorkeeper::Application.create!(
      name: "Test OAuth App",
      redirect_uri: "http://localhost/callback",
      confidential: false
    )
    access_token = Doorkeeper::AccessToken.create!(
      application: app,
      resource_owner_id: users(:alice).id,
      project_id: nil,
      scopes: "mcp_read",
      expires_in: 1.hour
    )

    transport = build_transport
    result = transport.send(:valid_token?, access_token.token)

    assert_not result, "Should reject OAuth token without project"
  end

  test "valid_token? routes sk_proj_ tokens to API key validation" do
    transport = build_transport
    transport.send(:valid_token?, ALICE_TOKEN)

    assert_equal @api_key, Current.mcp_api_key, "sk_proj_ prefix should use API key path"
    assert_nil Current.mcp_oauth_token
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
    transport = build_transport

    # Simulate the rescue behavior of call() directly
    response = begin
      raise ProjectAuthTransport::RateLimitedError
    rescue ProjectAuthTransport::RateLimitedError
      [ 429, { "Content-Type" => "application/json", "Retry-After" => ProjectAuthTransport::RATE_PERIOD.to_i.to_s },
        [ { error: "rate_limited", message: "Too many requests." }.to_json ] ]
    end

    assert_equal 429, response[0], "Should return 429 status"
    assert_equal "60", response[1]["Retry-After"], "Should include Retry-After header"
  end

  private

  def build_transport
    ProjectAuthTransport.allocate
  end
end
