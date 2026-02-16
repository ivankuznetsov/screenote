# frozen_string_literal: true

require "test_helper"

class OauthMetadataControllerTest < ActionDispatch::IntegrationTest
  test "protected_resource returns RFC 9728 metadata" do
    get "/.well-known/oauth-protected-resource"

    assert_response :success
    json = JSON.parse(response.body)

    assert_includes json["resource"], "/mcp", "resource should include MCP path"
    assert_kind_of Array, json["authorization_servers"], "authorization_servers should be an array"
    assert_equal [ "header" ], json["bearer_methods_supported"]
  end

  test "authorization_server returns RFC 8414 metadata" do
    get "/.well-known/oauth-authorization-server"

    assert_response :success
    json = JSON.parse(response.body)

    assert_includes json["authorization_endpoint"], "/oauth/authorize"
    assert_includes json["token_endpoint"], "/oauth/token"
    assert_includes json["registration_endpoint"], "/oauth/register"
    assert_equal [ "code" ], json["response_types_supported"]
    assert_equal [ "S256" ], json["code_challenge_methods_supported"]
    assert_includes json["grant_types_supported"], "authorization_code"
    assert_includes json["token_endpoint_auth_methods_supported"], "none"
    assert_includes json["scopes_supported"], "mcp_read"
    assert_includes json["scopes_supported"], "mcp_write"
  end

  test "metadata endpoints do not require authentication" do
    get "/.well-known/oauth-protected-resource"
    assert_response :success, "Protected resource metadata should be public"

    get "/.well-known/oauth-authorization-server"
    assert_response :success, "Authorization server metadata should be public"
  end
end
