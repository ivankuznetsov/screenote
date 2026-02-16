# frozen_string_literal: true

require "test_helper"

class OauthFlowTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:alice)
    @project = projects(:alice_project)
  end

  test "full PKCE authorization code flow" do
    client_id = register_oauth_client
    code_verifier, code_challenge = generate_pkce_challenge

    sign_in(@user)

    auth_code = authorize_oauth_client(
      client_id: client_id,
      code_challenge: code_challenge
    )

    assert auth_code.present?, "Should receive authorization code"

    post "/oauth/token", params: {
      grant_type: "authorization_code",
      code: auth_code,
      redirect_uri: "http://localhost:9999/callback",
      client_id: client_id,
      code_verifier: code_verifier
    }

    assert_response :success
    token_response = JSON.parse(response.body)
    access_token = token_response["access_token"]
    refresh_token = token_response["refresh_token"]

    assert access_token.present?, "Should receive access token"
    assert refresh_token.present?, "Should receive refresh token"
    assert_equal "bearer", token_response["token_type"].downcase
    assert token_response["expires_in"].present?, "Should have expiration"

    db_token = Doorkeeper::AccessToken.by_token(access_token)
    assert_equal @user.id, db_token.resource_owner_id, "Token should be scoped to user"
  end

  test "authorization requires authentication" do
    client = create_oauth_application(redirect_uri: "http://localhost/callback")

    get "/oauth/authorize", params: {
      client_id: client.uid,
      redirect_uri: "http://localhost/callback",
      response_type: "code",
      scope: "mcp_read",
      code_challenge: "test",
      code_challenge_method: "S256"
    }

    assert_response :redirect
    assert_includes response.location, "session", "Should redirect to login"
  end

  test "token exchange fails without PKCE verifier" do
    client_id = register_oauth_client
    code_verifier, code_challenge = generate_pkce_challenge

    sign_in(@user)

    auth_code = authorize_oauth_client(
      client_id: client_id,
      code_challenge: code_challenge
    )

    post "/oauth/token", params: {
      grant_type: "authorization_code",
      code: auth_code,
      redirect_uri: "http://localhost:9999/callback",
      client_id: client_id
    }

    assert_response :bad_request, "Should reject token request without PKCE verifier"
  end

  test "refresh token flow" do
    client_id = register_oauth_client
    code_verifier, code_challenge = generate_pkce_challenge

    sign_in(@user)

    auth_code = authorize_oauth_client(
      client_id: client_id,
      code_challenge: code_challenge
    )

    post "/oauth/token", params: {
      grant_type: "authorization_code",
      code: auth_code,
      redirect_uri: "http://localhost:9999/callback",
      client_id: client_id,
      code_verifier: code_verifier
    }

    refresh_token = JSON.parse(response.body)["refresh_token"]

    post "/oauth/token", params: {
      grant_type: "refresh_token",
      refresh_token: refresh_token,
      client_id: client_id
    }

    assert_response :success
    new_token_response = JSON.parse(response.body)
    assert new_token_response["access_token"].present?, "Should receive new access token"
    assert new_token_response["refresh_token"].present?, "Should receive new refresh token"
  end

  test "metadata discovery endpoints are accessible" do
    get "/.well-known/oauth-protected-resource"
    assert_response :success
    resource_meta = JSON.parse(response.body)
    assert resource_meta["authorization_servers"].present?
    assert_includes resource_meta["scopes_supported"], "mcp_read", "Should include scopes_supported"

    get "/.well-known/oauth-authorization-server"
    assert_response :success
    server_meta = JSON.parse(response.body)

    assert server_meta["authorization_endpoint"].present?
    assert server_meta["token_endpoint"].present?
    assert server_meta["registration_endpoint"].present?
    assert_equal false, server_meta["client_id_metadata_document_supported"], "Should indicate CIMD not supported"
  end

  test "DCR rejects non-localhost redirect URIs" do
    post "/oauth/register", params: {
      client_name: "Evil Client",
      redirect_uris: [ "https://evil.example.com/callback" ]
    }, as: :json

    assert_response :bad_request
    json = JSON.parse(response.body)
    assert_equal "invalid_client_metadata", json["error"]
    assert_includes json["error_description"], "localhost"
  end

  test "DCR response includes RFC 7591 recommended fields" do
    post "/oauth/register", params: {
      client_name: "RFC Test",
      redirect_uris: [ "http://localhost:9999/callback" ]
    }, as: :json

    assert_response :created
    json = JSON.parse(response.body)
    assert json["client_id_issued_at"].present?, "Should include client_id_issued_at"
    assert_equal 0, json["client_secret_expires_at"], "Should include client_secret_expires_at"
  end
end
