# frozen_string_literal: true

require "test_helper"

class OauthFlowTest < ActionDispatch::IntegrationTest
  LOOPBACK_REDIRECT_URI = "http://127.0.0.1:9999/callback"

  setup do
    @user = users(:alice)
    @project = projects(:alice_project)
    @foreign_project = projects(:bob_project)
    Oauth::DynamicClientRegistrationRateLimiter.reset!
  end

  teardown do
    Oauth::DynamicClientRegistrationRateLimiter.reset!
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
      redirect_uri: LOOPBACK_REDIRECT_URI,
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
    assert_equal "user", db_token.principal_kind
    assert_nil db_token.project_id
  end

  test "authorization requires authentication" do
    client = create_oauth_application(redirect_uri: "http://127.0.0.1/callback")

    get "/oauth/authorize", params: {
      client_id: client.uid,
      redirect_uri: "http://127.0.0.1/callback",
      response_type: "code",
      scope: "mcp_read",
      code_challenge: "test",
      code_challenge_method: "S256"
    }

    assert_response :redirect
    assert_includes response.location, "session", "Should redirect to login"
  end

  test "authorization consent uses application wording for the Screenote CLI" do
    client = create_oauth_application(name: "Screenote CLI", redirect_uri: LOOPBACK_REDIRECT_URI)
    _verifier, code_challenge = generate_pkce_challenge
    sign_in(@user)

    get "/oauth/authorize", params: {
      client_id: client.uid,
      redirect_uri: LOOPBACK_REDIRECT_URI,
      response_type: "code",
      scope: "mcp_read mcp_write",
      code_challenge: code_challenge,
      code_challenge_method: "S256"
    }

    assert_response :success
    assert_select ".oauth-consent__explanation", text: /collaboration administration/i
    assert_select ".oauth-consent__scope-item", text: /project members, invitations, and their email addresses/i
    assert_select ".oauth-consent__scope-item", text: /including removing members/i
    assert_no_match(/Model Context Protocol/, response.body)
  end

  test "denying authorization creates no credential and returns access denied" do
    client = create_oauth_application(name: "Denied client", redirect_uri: LOOPBACK_REDIRECT_URI)
    _verifier, code_challenge = generate_pkce_challenge
    sign_in(@user)
    oauth_params = authorization_request_params(client: client, code_challenge: code_challenge)

    get "/oauth/authorize", params: oauth_params
    assert_response :success
    assert_select "form.oauth-consent__deny[method='post']" do
      assert_select "input[name='_method'][value='delete']"
    end

    assert_no_difference [ "Doorkeeper::AccessGrant.count", "Doorkeeper::AccessToken.count" ] do
      delete "/oauth/authorize", params: oauth_params
    end

    assert_response :redirect
    query = Rack::Utils.parse_query(URI.parse(response.location).query)
    assert_equal "access_denied", query.fetch("error")
    assert_equal "principal-state", query.fetch("state")
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
      redirect_uri: LOOPBACK_REDIRECT_URI,
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
      redirect_uri: LOOPBACK_REDIRECT_URI,
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

    refreshed_token = Doorkeeper::AccessToken.by_token(new_token_response["access_token"])
    assert_equal "user", refreshed_token.principal_kind
    assert_nil refreshed_token.project_id
  end

  test "migration-shaped token and confidential client digests remain usable" do
    client_uid = "migration-client-#{SecureRandom.hex(16)}"
    raw_client_secret = "migration-secret-#{SecureRandom.hex(24)}"
    raw_access_token = "migration-access-#{SecureRandom.hex(24)}"
    raw_refresh_token = "migration-refresh-#{SecureRandom.hex(24)}"
    client_secret_digest = Digest::SHA256.hexdigest(raw_client_secret)
    access_token_digest = Digest::SHA256.hexdigest(raw_access_token)
    refresh_token_digest = Digest::SHA256.hexdigest(raw_refresh_token)
    now = Time.current

    Doorkeeper::Application.insert_all!([ {
      name: "Migrated confidential client",
      uid: client_uid,
      secret: client_secret_digest,
      redirect_uri: LOOPBACK_REDIRECT_URI,
      scopes: "mcp_read mcp_write",
      confidential: true,
      dynamic: false,
      created_at: now,
      updated_at: now
    } ])
    client = Doorkeeper::Application.by_uid_and_secret(client_uid, raw_client_secret)
    assert client
    assert_equal client_secret_digest, client[:secret]

    Doorkeeper::AccessToken.insert_all!([ {
      application_id: client.id,
      resource_owner_id: @user.id,
      token: access_token_digest,
      refresh_token: refresh_token_digest,
      previous_refresh_token: "",
      expires_in: 1.year.to_i,
      scopes: "mcp_read mcp_write",
      principal_kind: "project",
      project_id: @project.id,
      created_at: now
    } ])

    migrated_token = Doorkeeper::AccessToken.by_token(raw_access_token)
    assert migrated_token
    assert_equal access_token_digest, migrated_token[:token]
    assert_equal refresh_token_digest, migrated_token[:refresh_token]
    assert_equal @user.id, migrated_token.resource_owner_id
    assert_equal "project", migrated_token.principal_kind
    assert_equal @project.id, migrated_token.project_id

    post "/oauth/token", params: {
      grant_type: "refresh_token",
      refresh_token: raw_refresh_token,
      client_id: client_uid,
      client_secret: raw_client_secret
    }

    assert_response :success
    refreshed_token = Doorkeeper::AccessToken.by_token(response.parsed_body.fetch("access_token"))
    assert_equal @user.id, refreshed_token.resource_owner_id
    assert_equal "project", refreshed_token.principal_kind
    assert_equal @project.id, refreshed_token.project_id
  end

  test "project consent binds the authorization code token and refresh rotation to that project" do
    client = create_oauth_application(name: "Project client", redirect_uri: LOOPBACK_REDIRECT_URI)
    code_verifier, code_challenge = generate_pkce_challenge
    sign_in(@user)
    oauth_params = authorization_request_params(client: client, code_challenge: code_challenge)

    get "/oauth/authorize", params: oauth_params
    assert_response :success
    assert_select "select[data-testid='oauth-principal-select']" do
      assert_select "option[value='']", text: /all current projects/i
      assert_select "option[value='#{@project.id}']", text: @project.name
      assert_select "option[value='#{@foreign_project.id}']", count: 0
    end

    assert_difference "Doorkeeper::AccessGrant.count", 1 do
      post "/oauth/authorize", params: oauth_params.merge(principal_project_id: @project.id)
    end
    assert_response :redirect

    authorization_code = authorization_code_from_response
    grant = Doorkeeper::AccessGrant.by_token(authorization_code)
    assert_equal @user.id, grant.resource_owner_id
    assert_equal "project", grant.principal_kind
    assert_equal @project.id, grant.project_id

    token_response = exchange_authorization_code(
      authorization_code,
      client: client,
      code_verifier: code_verifier
    )
    token = Doorkeeper::AccessToken.by_token(token_response.fetch("access_token"))
    assert_equal @user.id, token.resource_owner_id
    assert_equal "project", token.principal_kind
    assert_equal @project.id, token.project_id

    post "/oauth/token", params: {
      grant_type: "refresh_token",
      refresh_token: token_response.fetch("refresh_token"),
      client_id: client.uid
    }

    assert_response :success
    refreshed_token = Doorkeeper::AccessToken.by_token(response.parsed_body.fetch("access_token"))
    assert_equal @user.id, refreshed_token.resource_owner_id
    assert_equal "project", refreshed_token.principal_kind
    assert_equal @project.id, refreshed_token.project_id
  end

  test "foreign project consent is rejected without creating a grant or token" do
    client = create_oauth_application(name: "Foreign project client", redirect_uri: LOOPBACK_REDIRECT_URI)
    _code_verifier, code_challenge = generate_pkce_challenge
    sign_in(@user)
    oauth_params = authorization_request_params(client: client, code_challenge: code_challenge)

    get "/oauth/authorize", params: oauth_params
    assert_response :success

    assert_no_difference [ "Doorkeeper::AccessGrant.count", "Doorkeeper::AccessToken.count" ] do
      post "/oauth/authorize", params: oauth_params.merge(principal_project_id: @foreign_project.id)
    end

    assert_response :unprocessable_entity
    assert_select "[data-testid='oauth-principal-error']", text: /currently belong to/i
  end

  test "project consent is rejected when membership becomes stale before submission" do
    project = @foreign_project
    membership = project.project_memberships.create!(user: @user, role: :member)
    client = create_oauth_application(name: "Stale membership client", redirect_uri: LOOPBACK_REDIRECT_URI)
    _code_verifier, code_challenge = generate_pkce_challenge
    sign_in(@user)
    oauth_params = authorization_request_params(client: client, code_challenge: code_challenge)

    get "/oauth/authorize", params: oauth_params
    assert_response :success
    assert_select "option[value='#{project.id}']", text: project.name
    membership.destroy!

    assert_no_difference [ "Doorkeeper::AccessGrant.count", "Doorkeeper::AccessToken.count" ] do
      post "/oauth/authorize", params: oauth_params.merge(principal_project_id: project.id)
    end

    assert_response :unprocessable_entity
    assert_select "[data-testid='oauth-principal-error']", text: /currently belong to/i
  end

  test "a project grant cannot mint a token after membership becomes stale" do
    project = @foreign_project
    membership = project.project_memberships.create!(user: @user, role: :member)
    client = create_oauth_application(name: "Stale grant client", redirect_uri: LOOPBACK_REDIRECT_URI)
    code_verifier, code_challenge = generate_pkce_challenge
    sign_in(@user)
    oauth_params = authorization_request_params(client: client, code_challenge: code_challenge)

    get "/oauth/authorize", params: oauth_params
    post "/oauth/authorize", params: oauth_params.merge(principal_project_id: project.id)
    assert_response :redirect
    authorization_code = authorization_code_from_response
    assert_equal "project", Doorkeeper::AccessGrant.by_token(authorization_code).principal_kind
    membership.destroy!

    assert_no_difference "Doorkeeper::AccessToken.count" do
      post "/oauth/token", params: {
        grant_type: "authorization_code",
        code: authorization_code,
        redirect_uri: client.redirect_uri,
        client_id: client.uid,
        code_verifier: code_verifier
      }
    end

    assert_response :bad_request
    assert_equal "invalid_grant", response.parsed_body["error"]
  end

  test "a project refresh credential cannot rotate after membership becomes stale" do
    project = @foreign_project
    membership = project.project_memberships.create!(user: @user, role: :member)
    client = create_oauth_application(name: "Stale refresh client", redirect_uri: LOOPBACK_REDIRECT_URI)
    code_verifier, code_challenge = generate_pkce_challenge
    sign_in(@user)
    oauth_params = authorization_request_params(client: client, code_challenge: code_challenge)

    get "/oauth/authorize", params: oauth_params
    post "/oauth/authorize", params: oauth_params.merge(principal_project_id: project.id)
    token_response = exchange_authorization_code(
      authorization_code_from_response,
      client: client,
      code_verifier: code_verifier
    )
    membership.destroy!

    assert_no_difference "Doorkeeper::AccessToken.count" do
      post "/oauth/token", params: {
        grant_type: "refresh_token",
        refresh_token: token_response.fetch("refresh_token"),
        client_id: client.uid
      }
    end

    assert_response :bad_request
    assert_equal "invalid_grant", response.parsed_body["error"]
  end

  test "an authorization request cannot preselect a project" do
    client = create_oauth_application(name: "Untrusted query client", redirect_uri: LOOPBACK_REDIRECT_URI)
    _code_verifier, code_challenge = generate_pkce_challenge
    sign_in(@user)

    assert_no_difference [ "Doorkeeper::AccessGrant.count", "Doorkeeper::AccessToken.count" ] do
      get "/oauth/authorize", params: authorization_request_params(
        client: client,
        code_challenge: code_challenge
      ).merge(principal_project_id: @project.id)
    end

    assert_response :success
    assert_select "option[value='#{@project.id}'][selected]", count: 0
  end

  test "client supplied principal attributes cannot substitute for server consent" do
    client = create_oauth_application(name: "Attribute injection client", redirect_uri: LOOPBACK_REDIRECT_URI)
    _code_verifier, code_challenge = generate_pkce_challenge
    sign_in(@user)
    oauth_params = authorization_request_params(client: client, code_challenge: code_challenge)

    get "/oauth/authorize", params: oauth_params.merge(
      principal_kind: "project",
      project_id: @project.id
    )
    assert_response :success

    post "/oauth/authorize", params: oauth_params.merge(
      principal_kind: "project",
      project_id: @project.id
    )
    assert_response :redirect

    grant = Doorkeeper::AccessGrant.by_token(authorization_code_from_response)
    assert_equal "user", grant.principal_kind
    assert_nil grant.project_id
  end

  test "deleting a consented project invalidates its refresh credential" do
    project = @user.owned_projects.create!(name: "Disposable consent project")
    client = create_oauth_application(name: "Disposable project client", redirect_uri: LOOPBACK_REDIRECT_URI)
    code_verifier, code_challenge = generate_pkce_challenge
    sign_in(@user)
    oauth_params = authorization_request_params(client: client, code_challenge: code_challenge)

    get "/oauth/authorize", params: oauth_params
    post "/oauth/authorize", params: oauth_params.merge(principal_project_id: project.id)
    token_response = exchange_authorization_code(
      authorization_code_from_response,
      client: client,
      code_verifier: code_verifier
    )
    token_id = Doorkeeper::AccessToken.by_token(token_response.fetch("access_token")).id

    project.destroy!

    assert_not Doorkeeper::AccessToken.exists?(token_id)
    assert_no_difference "Doorkeeper::AccessToken.count" do
      post "/oauth/token", params: {
        grant_type: "refresh_token",
        refresh_token: token_response.fetch("refresh_token"),
        client_id: client.uid
      }
    end
    assert_response :bad_request
    assert_equal "invalid_grant", response.parsed_body["error"]
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

  test "DCR rejects non-loopback redirect URIs" do
    post "/oauth/register", params: {
      client_name: "Evil Client",
      redirect_uris: [ "https://evil.example.com/callback" ]
    }, as: :json

    assert_response :bad_request
    json = JSON.parse(response.body)
    assert_equal "invalid_client_metadata", json["error"]
    assert_includes json["error_description"], "127.0.0.1"
  end

  test "DCR response includes RFC 7591 recommended fields" do
    post "/oauth/register", params: {
      client_name: "RFC Test",
      redirect_uris: [ LOOPBACK_REDIRECT_URI ]
    }, as: :json

    assert_response :created
    json = JSON.parse(response.body)
    assert json["client_id_issued_at"].present?, "Should include client_id_issued_at"
    assert_equal 0, json["client_secret_expires_at"], "Should include client_secret_expires_at"
  end

  private

  def authorization_request_params(client:, code_challenge:, scope: "mcp_read mcp_write")
    {
      client_id: client.uid,
      redirect_uri: client.redirect_uri,
      response_type: "code",
      scope: scope,
      code_challenge: code_challenge,
      code_challenge_method: "S256",
      state: "principal-state"
    }
  end

  def authorization_code_from_response
    Rack::Utils.parse_query(URI.parse(response.location).query).fetch("code")
  end

  def exchange_authorization_code(authorization_code, client:, code_verifier:)
    post "/oauth/token", params: {
      grant_type: "authorization_code",
      code: authorization_code,
      redirect_uri: client.redirect_uri,
      client_id: client.uid,
      code_verifier: code_verifier
    }

    assert_response :success
    response.parsed_body
  end
end
