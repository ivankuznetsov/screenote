# frozen_string_literal: true

require "test_helper"

module Api
  module V1
    class ProjectsControllerTest < ActionDispatch::IntegrationTest
      ALICE_TOKEN = "sk_proj_test_alice_key_000000000000000000000000"

      test "lists the project bound to the api key" do
        get api_v1_projects_path, headers: auth_header(ALICE_TOKEN)

        assert_response :success
        body = response.parsed_body
        assert_equal [ projects(:alice_project).id ], body["projects"].map { |project| project["id"] }
        assert_equal "api_key", body["projects"].first["role"]
        assert body["projects"].first.key?("screenshot_count")
      end

      test "returns stable unauthorized json without an api key" do
        get api_v1_projects_path

        assert_response :unauthorized
        assert_equal "Invalid or missing bearer token", response.parsed_body["error"]
        assert_equal "unauthorized", response.parsed_body["code"]
      end

      test "oauth read token lists all user projects with membership roles" do
        token = oauth_token(user: users(:alice), scopes: "mcp_read")

        get api_v1_projects_path, headers: auth_header(token.token)

        assert_response :success
        body = response.parsed_body
        assert_equal [ projects(:alice_project).id, projects(:alice_second_project).id ].sort,
          body["projects"].map { |project| project["id"] }.sort
        assert body["projects"].all? { |project| project["role"].present? }
      end

      test "oauth write-only token cannot list projects" do
        token = oauth_token(user: users(:alice), scopes: "mcp_write")

        get api_v1_projects_path, headers: auth_header(token.token)

        assert_response :forbidden
        assert_equal "insufficient_scope", response.parsed_body["code"]
      end

      test "unknown non-api-key bearer token is unauthorized" do
        get api_v1_projects_path, headers: auth_header("garbage-oauth-token-not-sk-prefixed")

        assert_response :unauthorized
        assert_equal "unauthorized", response.parsed_body["code"]
      end

      test "revoked and expired oauth tokens are unauthorized" do
        revoked = oauth_token(user: users(:alice), revoked_at: 1.minute.ago)
        expired = oauth_token(user: users(:alice), expires_in: -1.minute)

        get api_v1_projects_path, headers: auth_header(revoked.token)
        assert_response :unauthorized

        get api_v1_projects_path, headers: auth_header(expired.token)
        assert_response :unauthorized
      end

      private

      def auth_header(token)
        { "Authorization" => "Bearer #{token}" }
      end

      def oauth_token(user:, scopes: "mcp_read", expires_in: 1.year, revoked_at: nil)
        create_oauth_token(application: create_oauth_application, user: user, scopes: scopes, expires_in: expires_in, revoked_at: revoked_at)
      end
    end
  end
end
