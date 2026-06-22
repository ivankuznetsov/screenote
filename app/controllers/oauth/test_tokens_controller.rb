# frozen_string_literal: true

module Oauth
  # Non-interactive token-minting endpoint for hive's OAuth/MCP integration
  # tests. Lets an external test suite obtain a valid mcp_read/mcp_write
  # access token WITHOUT browser consent, so it can exercise the real MCP
  # tools against a dedicated throwaway test project.
  #
  # SECURITY (fail closed):
  #   - Gated on a server-side secret in ENV["SCREENOTE_MCP_TEST_TOKEN_SECRET"].
  #     If that env var is blank, or the presented secret does not match (via a
  #     constant-time compare), the endpoint responds 404 — it does not even
  #     advertise that it exists. It is NOT gated on Rails.env, so it is safe to
  #     leave deployed; the secret is the only gate.
  #   - The token is ALWAYS minted for a single FIXED, clearly-named test
  #     identity (TEST_USER_EMAIL / TEST_PROJECT_NAME). It can never mint a
  #     token for an arbitrary or real user/project, so even if the endpoint
  #     were reachable in production the token could only touch the throwaway
  #     test project.
  class TestTokensController < ActionController::API
    TEST_USER_EMAIL = "hive-mcp-ci@screenote.test"
    TEST_PROJECT_NAME = "hive-mcp-ci"
    TEST_APPLICATION_NAME = "hive-mcp-ci-test-client"
    TOKEN_SCOPES = "mcp_read mcp_write"

    # POST /oauth/test_token
    def create
      return head(:not_found) unless authorized?

      user = find_or_create_test_user
      find_or_create_test_project(user)
      token = mint_token(user)

      render json: {
        access_token: token.token,
        token_type: "Bearer",
        scope: token.scopes.to_s,
        expires_in: token.expires_in_seconds,
        created_at: token.created_at.to_i
      }
    end

    private

    # Fail closed: both the server secret must be configured AND the presented
    # secret must match it via a constant-time compare. Anything else => 404.
    def authorized?
      configured = ENV["SCREENOTE_MCP_TEST_TOKEN_SECRET"].to_s
      return false if configured.blank?

      presented = presented_secret
      return false if presented.blank?

      ActiveSupport::SecurityUtils.secure_compare(presented, configured)
    end

    def presented_secret
      header = request.authorization.to_s
      if header.start_with?("Bearer ")
        header.delete_prefix("Bearer ").strip
      else
        params[:secret].to_s
      end
    end

    def find_or_create_test_user
      User.find_or_create_by!(email: TEST_USER_EMAIL) do |u|
        u.password = SecureRandom.hex(24)
        u.confirmed_at = Time.current
      end
    end

    def find_or_create_test_project(user)
      user.owned_projects.find_or_create_by!(name: TEST_PROJECT_NAME)
    end

    def mint_token(user)
      Doorkeeper::AccessToken.create!(
        application: test_application,
        resource_owner_id: user.id,
        scopes: TOKEN_SCOPES,
        expires_in: Doorkeeper.config.access_token_expires_in,
        use_refresh_token: false
      )
    end

    def test_application
      Doorkeeper::Application.find_or_create_by!(name: TEST_APPLICATION_NAME) do |app|
        app.redirect_uri = "http://localhost/callback"
        app.scopes = TOKEN_SCOPES
        app.confidential = false
      end
    end
  end
end
