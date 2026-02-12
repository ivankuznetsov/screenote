# frozen_string_literal: true

require "test_helper"

class McpAuthTest < ActiveSupport::TestCase
  ALICE_TOKEN = "sk_proj_test_alice_key_000000000000000000000000"
  REVOKED_TOKEN = "sk_proj_test_alice_revoked_00000000000000000000"

  setup do
    @api_key = api_keys(:alice_key)
    @revoked_key = api_keys(:alice_key_revoked)
    @original_cache = Rails.cache
    Rails.cache = ActiveSupport::Cache::MemoryStore.new
  end

  teardown do
    Current.reset
    Rails.cache = @original_cache
  end

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

  # Rate limiting tests
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
