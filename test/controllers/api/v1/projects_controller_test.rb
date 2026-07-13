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

        expected_roles = users(:alice).project_memberships.index_by(&:project_id).transform_values(&:role)
        actual_roles = body["projects"].to_h { |project| [ project["id"], project["role"] ] }
        assert_equal expected_roles, actual_roles
      end

      test "project-scoped oauth token lists only its bound member project" do
        token = oauth_token(user: users(:alice), scopes: "mcp_read")
        token.update_column(:project_id, projects(:alice_project).id)

        get api_v1_projects_path, headers: auth_header(token.token)

        assert_response :success
        assert_equal [ projects(:alice_project).id ],
          response.parsed_body.fetch("projects").pluck("id")
      end

      test "oauth write-only token cannot list projects" do
        token = oauth_token(user: users(:alice), scopes: "mcp_write")

        get api_v1_projects_path, headers: auth_header(token.token)

        assert_response :forbidden
        assert_equal "insufficient_scope", response.parsed_body["code"]
      end

      test "oauth write token creates an owned project" do
        user = users(:free_user)
        token = oauth_token(user: user, scopes: "mcp_write")

        assert_difference [ "Project.count", "ProjectMembership.count" ], 1 do
          post api_v1_projects_path,
            params: { name: "CLI Project" },
            headers: auth_header(token.token),
            as: :json
        end

        assert_response :created
        body = response.parsed_body
        assert_equal %w[created_at id name role screenshot_count].sort, body.fetch("project").keys.sort
        assert_equal "CLI Project", body.dig("project", "name")
        assert_equal "owner", body.dig("project", "role")
        assert_equal 0, body.dig("project", "screenshot_count")

        project = Project.find(body.dig("project", "id"))
        assert_equal user, project.creator
        assert project.owner?(user)
      end

      test "project creation validates the name" do
        user = users(:free_user)
        token = oauth_token(user: user, scopes: "mcp_write")

        assert_no_difference [ "Project.count", "ProjectMembership.count" ] do
          post api_v1_projects_path,
            params: { name: "" },
            headers: auth_header(token.token),
            as: :json
        end

        assert_response :unprocessable_entity
        assert_equal "validation_failed", response.parsed_body["code"]
        assert_includes response.parsed_body["details"], "Name can't be blank"
      end

      test "project creation rejects a structured name" do
        user = users(:free_user)
        token = oauth_token(user: user, scopes: "mcp_write")

        assert_no_difference [ "Project.count", "ProjectMembership.count" ] do
          post api_v1_projects_path,
            params: { name: [ "not a scalar" ] },
            headers: auth_header(token.token),
            as: :json
        end

        assert_response :unprocessable_entity
        assert_equal "validation_failed", response.parsed_body["code"]
        assert_includes response.parsed_body["details"], "Name can't be blank"
      end

      test "free plan project quota is enforced" do
        user = users(:free_user)
        user.owned_projects.create!(name: "Existing project")
        token = oauth_token(user: user, scopes: "mcp_write")

        assert_no_difference [ "Project.count", "ProjectMembership.count" ] do
          post api_v1_projects_path,
            params: { name: "Over quota" },
            headers: auth_header(token.token),
            as: :json
        end

        assert_response :forbidden
        assert_equal "project_limit_reached", response.parsed_body["code"]
      end

      test "api keys cannot create projects" do
        assert_no_difference "Project.count" do
          post api_v1_projects_path,
            params: { name: "Key project" },
            headers: auth_header(ALICE_TOKEN),
            as: :json
        end

        assert_response :forbidden
        assert_equal "forbidden", response.parsed_body["code"]
      end

      test "oauth read token cannot create projects" do
        token = oauth_token(user: users(:free_user), scopes: "mcp_read")

        assert_no_difference "Project.count" do
          post api_v1_projects_path,
            params: { name: "Read-only project" },
            headers: auth_header(token.token),
            as: :json
        end

        assert_response :forbidden
        assert_equal "insufficient_scope", response.parsed_body["code"]
      end

      test "project-scoped oauth tokens cannot create projects" do
        token = oauth_token(user: users(:alice), scopes: "mcp_write")
        token.update_column(:project_id, projects(:alice_project).id)

        assert_no_difference "Project.count" do
          post api_v1_projects_path,
            params: { name: "Cross-scope project" },
            headers: auth_header(token.token),
            as: :json
        end

        assert_response :forbidden
        assert_equal "forbidden", response.parsed_body["code"]
      end

      test "project deletion invalidates its project-scoped oauth token" do
        user = users(:alice)
        project = user.owned_projects.create!(name: "Disposable OAuth scope")
        token = oauth_token(user: user, scopes: "mcp_read")
        token.update_column(:project_id, project.id)
        raw_token = token.token

        project.destroy!

        get api_v1_projects_path, headers: auth_header(raw_token)

        assert_response :unauthorized
        assert_equal "unauthorized", response.parsed_body["code"]
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
