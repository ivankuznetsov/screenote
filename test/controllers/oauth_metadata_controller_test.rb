# frozen_string_literal: true

require "test_helper"

class OauthMetadataControllerTest < ActionDispatch::IntegrationTest
  DEVICE_GRANT_TYPE = "urn:ietf:params:oauth:grant-type:device_code"

  test "protected_resource returns RFC 9728 metadata" do
    get "/.well-known/oauth-protected-resource"

    assert_response :success
    json = JSON.parse(response.body)

    assert_equal "#{Screenote::Deployment.current.base_url}/mcp", json["resource"]
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
    assert_includes json["device_authorization_endpoint"], "/oauth/authorize_device"
    assert_equal [ "code" ], json["response_types_supported"]
    assert_equal [ "S256" ], json["code_challenge_methods_supported"]
    assert_includes json["grant_types_supported"], "authorization_code"
    assert_includes json["grant_types_supported"], DEVICE_GRANT_TYPE
    assert_includes json["token_endpoint_auth_methods_supported"], "none"
    assert_includes json["scopes_supported"], "mcp_read"
    assert_includes json["scopes_supported"], "mcp_write"
  end

  test "metadata never reflects a forged request host" do
    host! "attacker.example.test"

    get "/.well-known/oauth-authorization-server",
      headers: { "X-Forwarded-Host" => "forwarded-attacker.example.test" }

    assert_response :success
    json = response.parsed_body
    assert_equal Screenote::Deployment.current.base_url, json.fetch("issuer")
    assert_equal "#{Screenote::Deployment.current.base_url}/oauth/token", json.fetch("token_endpoint")
    assert_not_includes response.body, "attacker.example.test"
  end

  test "metadata endpoints do not require authentication" do
    get "/.well-known/oauth-protected-resource"
    assert_response :success, "Protected resource metadata should be public"

    get "/.well-known/oauth-authorization-server"
    assert_response :success, "Authorization server metadata should be public"
  end
end
