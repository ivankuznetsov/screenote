# frozen_string_literal: true

require "test_helper"

class OauthFlowTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:alice)
    @project = projects(:alice_project)
  end

  test "full PKCE authorization code flow" do
    # Step 1: Register client via DCR
    post "/oauth/register", params: {
      client_name: "Test MCP Client",
      redirect_uris: [ "http://localhost:9999/callback" ]
    }, as: :json

    assert_response :created
    client_id = JSON.parse(response.body)["client_id"]
    assert client_id.present?, "DCR should return client_id"

    # Step 2: Generate PKCE challenge
    code_verifier = SecureRandom.urlsafe_base64(32)
    code_challenge = Base64.urlsafe_encode64(
      Digest::SHA256.digest(code_verifier), padding: false
    )

    # Step 3: Sign in the user
    sign_in(@user)

    # Step 4: Request authorization
    get "/oauth/authorize", params: {
      client_id: client_id,
      redirect_uri: "http://localhost:9999/callback",
      response_type: "code",
      scope: "mcp_read",
      code_challenge: code_challenge,
      code_challenge_method: "S256",
      state: "test_state_123"
    }

    assert_response :success, "Should show authorization form"

    # Step 5: Approve authorization with project selection
    post "/oauth/authorize", params: {
      client_id: client_id,
      redirect_uri: "http://localhost:9999/callback",
      response_type: "code",
      scope: "mcp_read",
      code_challenge: code_challenge,
      code_challenge_method: "S256",
      state: "test_state_123",
      project_id: @project.id
    }

    assert_response :redirect
    callback_uri = URI.parse(response.location)
    callback_params = Rack::Utils.parse_query(callback_uri.query)
    auth_code = callback_params["code"]
    assert auth_code.present?, "Should receive authorization code"
    assert_equal "test_state_123", callback_params["state"], "State should be preserved"

    # Step 6: Exchange code for token
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

    # Step 7: Verify token has project_id
    db_token = Doorkeeper::AccessToken.by_token(access_token)
    assert_equal @project.id, db_token.project_id, "Token should be scoped to selected project"
  end

  test "authorization requires authentication" do
    client = Doorkeeper::Application.create!(
      name: "Test App",
      redirect_uri: "http://localhost/callback",
      confidential: false
    )

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
    # Register and authorize
    post "/oauth/register", params: {
      client_name: "No PKCE",
      redirect_uris: [ "http://localhost:9999/callback" ]
    }, as: :json
    client_id = JSON.parse(response.body)["client_id"]

    code_verifier = SecureRandom.urlsafe_base64(32)
    code_challenge = Base64.urlsafe_encode64(
      Digest::SHA256.digest(code_verifier), padding: false
    )

    sign_in(@user)

    get "/oauth/authorize", params: {
      client_id: client_id,
      redirect_uri: "http://localhost:9999/callback",
      response_type: "code",
      scope: "mcp_read",
      code_challenge: code_challenge,
      code_challenge_method: "S256"
    }

    post "/oauth/authorize", params: {
      client_id: client_id,
      redirect_uri: "http://localhost:9999/callback",
      response_type: "code",
      scope: "mcp_read",
      code_challenge: code_challenge,
      code_challenge_method: "S256",
      project_id: @project.id
    }

    callback_uri = URI.parse(response.location)
    auth_code = Rack::Utils.parse_query(callback_uri.query)["code"]

    # Try token exchange without code_verifier
    post "/oauth/token", params: {
      grant_type: "authorization_code",
      code: auth_code,
      redirect_uri: "http://localhost:9999/callback",
      client_id: client_id
    }

    assert_response :bad_request, "Should reject token request without PKCE verifier"
  end

  test "refresh token flow" do
    # Get initial tokens
    post "/oauth/register", params: {
      client_name: "Refresh Test",
      redirect_uris: [ "http://localhost:9999/callback" ]
    }, as: :json
    client_id = JSON.parse(response.body)["client_id"]

    code_verifier = SecureRandom.urlsafe_base64(32)
    code_challenge = Base64.urlsafe_encode64(
      Digest::SHA256.digest(code_verifier), padding: false
    )

    sign_in(@user)

    get "/oauth/authorize", params: {
      client_id: client_id,
      redirect_uri: "http://localhost:9999/callback",
      response_type: "code",
      scope: "mcp_read",
      code_challenge: code_challenge,
      code_challenge_method: "S256"
    }

    post "/oauth/authorize", params: {
      client_id: client_id,
      redirect_uri: "http://localhost:9999/callback",
      response_type: "code",
      scope: "mcp_read",
      code_challenge: code_challenge,
      code_challenge_method: "S256",
      project_id: @project.id
    }

    auth_code = Rack::Utils.parse_query(URI.parse(response.location).query)["code"]

    post "/oauth/token", params: {
      grant_type: "authorization_code",
      code: auth_code,
      redirect_uri: "http://localhost:9999/callback",
      client_id: client_id,
      code_verifier: code_verifier
    }

    refresh_token = JSON.parse(response.body)["refresh_token"]

    # Use refresh token
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

    server_url = resource_meta["authorization_servers"].first
    get "/.well-known/oauth-authorization-server"
    assert_response :success
    server_meta = JSON.parse(response.body)

    assert server_meta["authorization_endpoint"].present?
    assert server_meta["token_endpoint"].present?
    assert server_meta["registration_endpoint"].present?
  end
end
