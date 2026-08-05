# frozen_string_literal: true

module OauthTestHelper
  def create_oauth_application(name: "Test OAuth App", redirect_uri: "http://127.0.0.1/callback", confidential: false)
    Doorkeeper::Application.create!(
      name: name,
      redirect_uri: redirect_uri,
      confidential: confidential
    )
  end

  def create_oauth_token(
    application:,
    user:,
    project: nil,
    principal_kind: project.present? ? "project" : "user",
    scopes: "mcp_read",
    expires_in: 1.year,
    revoked_at: nil
  )
    access_token = Doorkeeper::AccessToken.create!(
      application: application,
      resource_owner_id: user.id,
      project_id: project&.id,
      principal_kind: principal_kind,
      scopes: scopes,
      expires_in: expires_in,
      revoked_at: revoked_at
    )

    expose_plaintext_token(access_token)
  end

  def generate_pkce_challenge
    verifier = SecureRandom.urlsafe_base64(32)
    challenge = Base64.urlsafe_encode64(Digest::SHA256.digest(verifier), padding: false)
    [ verifier, challenge ]
  end

  def register_oauth_client(name: "Test MCP Client", redirect_uri: "http://127.0.0.1:9999/callback")
    post "/oauth/register", params: {
      client_name: name,
      redirect_uris: [ redirect_uri ]
    }, as: :json

    JSON.parse(response.body)["client_id"]
  end

  def expose_plaintext_token(access_token)
    plaintext = access_token.plaintext_token
    return access_token if plaintext.blank? || plaintext == access_token[:token]

    # Keep the helper's existing `token.token` contract without changing the
    # one-way digest persisted by Doorkeeper.
    access_token.define_singleton_method(:token) { plaintext }
    access_token
  end

  def authorize_oauth_client(client_id:, redirect_uri: "http://127.0.0.1:9999/callback", scope: "mcp_read", code_challenge:, state: "test_state")
    get "/oauth/authorize", params: {
      client_id: client_id,
      redirect_uri: redirect_uri,
      response_type: "code",
      scope: scope,
      code_challenge: code_challenge,
      code_challenge_method: "S256",
      state: state
    }

    post "/oauth/authorize", params: {
      client_id: client_id,
      redirect_uri: redirect_uri,
      response_type: "code",
      scope: scope,
      code_challenge: code_challenge,
      code_challenge_method: "S256",
      state: state
    }

    Rack::Utils.parse_query(URI.parse(response.location).query)["code"]
  end
end
