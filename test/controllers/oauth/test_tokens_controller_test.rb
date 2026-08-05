# frozen_string_literal: true

require "test_helper"

module Oauth
  class TestTokensControllerTest < ActionDispatch::IntegrationTest
    SECRET = "test-mcp-ci-secret-value"

    setup do
      ENV["SCREENOTE_MCP_TEST_TOKEN_SECRET"] = SECRET
      @original_cache = Rails.cache
      Rails.cache = ActiveSupport::Cache::MemoryStore.new
    end

    teardown do
      ENV.delete("SCREENOTE_MCP_TEST_TOKEN_SECRET")
      Current.reset
      Rails.cache = @original_cache
    end

    # --- Happy path ---

    test "mints an OAuth token with mcp scopes when secret matches (Bearer header)" do
      post oauth_test_token_path, headers: { "Authorization" => "Bearer #{SECRET}" }

      assert_response :success
      body = JSON.parse(response.body)

      assert body["access_token"].present?, "Should return an access_token"
      assert_equal "Bearer", body["token_type"]
      assert_equal "mcp_read mcp_write", body["scope"]
      assert body["expires_in"].to_i.positive?, "Should report a positive expires_in"
      assert body["created_at"].present?, "Should report created_at"
    end

    test "accepts the secret via a secret param as well" do
      post oauth_test_token_path, params: { secret: SECRET }

      assert_response :success
      assert JSON.parse(response.body)["access_token"].present?
    end

    test "minted token is a real non-revoked Doorkeeper::AccessToken with mcp scopes" do
      post oauth_test_token_path, headers: { "Authorization" => "Bearer #{SECRET}" }
      assert_response :success

      raw = JSON.parse(response.body)["access_token"]
      access_token = Doorkeeper::AccessToken.by_token(raw)

      assert access_token.present?, "Token should resolve via Doorkeeper::AccessToken.by_token"
      assert_not access_token.revoked?, "Token should not be revoked"
      assert_not access_token.expired?, "Token should not be expired"
      assert_equal %w[mcp_read mcp_write].sort, access_token.scopes.to_a.sort
      assert_equal test_project.id, access_token.project_id, "Token should be scoped to the fixed test project"
    end

    test "token resolves through validate_oauth_token to the fixed test user and project" do
      post oauth_test_token_path, headers: { "Authorization" => "Bearer #{SECRET}" }
      raw = JSON.parse(response.body)["access_token"]

      # Drive the SAME code path the MCP middleware uses.
      transport = ProjectAuthTransport.allocate
      result = transport.send(:valid_token?, raw)

      assert result, "ProjectAuthTransport#valid_token? should accept the minted token"
      principal = Current.authenticated_principal
      assert_equal TestTokensController::TEST_USER_EMAIL, principal.user.email,
        "valid_token? should resolve the fixed test identity"
      assert_equal test_project, principal.project,
        "Project-scoped token should resolve the fixed test project"
      assert_nil principal.api_key, "OAuth path must not set an API key"
    end

    test "minted token can only resolve the fixed project through tools" do
      post oauth_test_token_path, headers: { "Authorization" => "Bearer #{SECRET}" }
      raw = JSON.parse(response.body)["access_token"]

      transport = ProjectAuthTransport.allocate
      transport.send(:valid_token?, raw)

      project = test_project
      current_user = Current.authenticated_principal.user
      other_project = current_user.owned_projects.create!(name: "not-for-test-token")

      assert_equal current_user, project.creator, "Test user is the project creator"
      assert_equal :owner, project.role_for(current_user),
        "Test user is an owner member (so user.projects includes it)"

      fixed_result = JSON.parse(ListScreenshotsTool.new.call(project_id: project.id))
      assert fixed_result.key?("screenshots"), "Fixed project should be usable"

      other_result = JSON.parse(ListScreenshotsTool.new.call(project_id: other_project.id))
      assert_equal "forbidden", other_result["error"], "Project-scoped token must not access another owned project"
    end

    test "minted token cannot list or create projects outside the fixed project" do
      post oauth_test_token_path, headers: { "Authorization" => "Bearer #{SECRET}" }
      raw = JSON.parse(response.body)["access_token"]

      transport = ProjectAuthTransport.allocate
      transport.send(:valid_token?, raw)
      Current.authenticated_principal.user.owned_projects.create!(name: "hidden-from-test-token")

      listed = JSON.parse(ListProjectsTool.new.call)
      assert_equal [ test_project.id ], listed["projects"].map { |project| project["id"] }

      created = JSON.parse(CreateProjectTool.new.call(name: "blocked"))
      assert_equal "forbidden", created["error"]
    end

    # --- Gating: fail closed ---

    test "returns 404 when the env secret is unset" do
      ENV.delete("SCREENOTE_MCP_TEST_TOKEN_SECRET")

      post oauth_test_token_path, headers: { "Authorization" => "Bearer #{SECRET}" }

      assert_response :not_found
      assert response.body.blank?, "404 should not leak a body"
    end

    test "returns 404 when the env secret is blank" do
      ENV["SCREENOTE_MCP_TEST_TOKEN_SECRET"] = "   "

      post oauth_test_token_path, headers: { "Authorization" => "Bearer #{SECRET}" }

      assert_response :not_found
    end

    test "returns 404 when the presented secret is wrong" do
      post oauth_test_token_path, headers: { "Authorization" => "Bearer wrong-secret" }

      assert_response :not_found
    end

    test "returns 404 when no secret is presented at all" do
      post oauth_test_token_path

      assert_response :not_found
    end

    test "does not mint any token when unauthorized" do
      assert_no_difference -> { Doorkeeper::AccessToken.count } do
        post oauth_test_token_path, headers: { "Authorization" => "Bearer wrong" }
      end
      assert_response :not_found
    end

    # --- Idempotent test identity ---

    test "re-calling reuses the same test user and project (no duplicates)" do
      post oauth_test_token_path, headers: { "Authorization" => "Bearer #{SECRET}" }
      assert_response :success
      post oauth_test_token_path, headers: { "Authorization" => "Bearer #{SECRET}" }
      assert_response :success

      assert_equal 1, User.where(email: TestTokensController::TEST_USER_EMAIL).count,
        "Should not duplicate the test user"

      user = User.find_by(email: TestTokensController::TEST_USER_EMAIL)
      assert_equal 1, user.owned_projects.where(name: TestTokensController::TEST_PROJECT_NAME).count,
        "Should not duplicate the test project"
      assert_equal 1, Doorkeeper::Application.where(name: TestTokensController::TEST_APPLICATION_NAME).count,
        "Should not duplicate the test OAuth application"
    end

    test "each call mints a fresh, independently-valid token" do
      post oauth_test_token_path, headers: { "Authorization" => "Bearer #{SECRET}" }
      first = JSON.parse(response.body)["access_token"]
      post oauth_test_token_path, headers: { "Authorization" => "Bearer #{SECRET}" }
      second = JSON.parse(response.body)["access_token"]

      assert_not_equal first, second, "Each call should mint a distinct token"
      assert Doorkeeper::AccessToken.by_token(first).present?
      assert Doorkeeper::AccessToken.by_token(second).present?
    end

    private

    def test_project
      User.find_by!(email: TestTokensController::TEST_USER_EMAIL)
        .owned_projects.find_by!(name: TestTokensController::TEST_PROJECT_NAME)
    end
  end
end
