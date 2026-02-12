# frozen_string_literal: true

require "test_helper"

class McpAuthTest < ActiveSupport::TestCase
  setup do
    @api_key = api_keys(:alice_key)
    @revoked_key = api_keys(:alice_key_revoked)
  end

  teardown do
    Thread.current[:mcp_current_project] = nil
    Thread.current[:mcp_current_api_key] = nil
  end

  test "valid_token? accepts active API key" do
    transport = build_transport
    result = transport.send(:valid_token?, @api_key.token)

    assert result, "Should accept valid active token"
    assert_equal @api_key.project, Thread.current[:mcp_current_project]
    assert_equal @api_key, Thread.current[:mcp_current_api_key]
  end

  test "valid_token? rejects revoked API key" do
    transport = build_transport
    result = transport.send(:valid_token?, @revoked_key.token)

    assert_not result, "Should reject revoked token"
    assert_nil Thread.current[:mcp_current_project]
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

    transport.send(:valid_token?, @api_key.token)

    assert @api_key.reload.last_used_at > old_time, "Should update last_used_at"
  end

  private

  def build_transport
    ProjectAuthTransport.allocate
  end
end
