# frozen_string_literal: true

require "test_helper"

module Api
  module V1
    class AnnotationResolutionsControllerTest < ActionDispatch::IntegrationTest
      ALICE_TOKEN = "sk_proj_test_alice_key_000000000000000000000000"

      test "api key resolves its project annotation and authors the audit comment" do
        annotation = annotations(:point_annotation)

        assert_difference -> { annotation.annotation_comments.count }, 1 do
          post resolve_path(annotation),
            params: { comment: "Fixed by the CLI" },
            headers: auth_header(ALICE_TOKEN),
            as: :json
        end

        assert_response :success
        body = response.parsed_body
        assert body["success"]
        assert_equal "resolved", body["operation"]
        assert_equal "resolved", body.dig("annotation", "status")
        assert_equal "Fixed by the CLI", body.dig("comment", "body")
        assert_equal "resolved", body.dig("comment", "action")

        resolution = annotation.reload.annotation_comments.last
        assert_equal api_keys(:alice_key), resolution.api_key
        assert_nil resolution.user
        assert_equal api_keys(:alice_key), annotation.resolved_by_api_key
      end

      test "oauth write token resolves an annotation as the current user" do
        annotation = annotations(:point_annotation)
        user = users(:alice)
        token = oauth_token(user: user, scopes: "mcp_write")

        post resolve_path(annotation),
          params: { project_id: projects(:alice_project).id, comment: "OAuth fix" },
          headers: auth_header(token.token),
          as: :json

        assert_response :success
        resolution = annotation.reload.annotation_comments.last
        assert_equal user, resolution.user
        assert_nil resolution.api_key
        assert_equal user, annotation.resolved_by_user
      end

      test "project-scoped oauth token resolves within its issued project" do
        annotation = annotations(:point_annotation)
        user = users(:alice)
        token = oauth_token(
          user: user,
          project: projects(:alice_project),
          scopes: "mcp_write"
        )

        post resolve_path(annotation),
          params: { project_id: projects(:alice_project).id },
          headers: auth_header(token.token),
          as: :json

        assert_response :success
        assert_equal "resolved", response.parsed_body.dig("annotation", "status")
        assert_equal user, annotation.reload.resolved_by_user
      end

      test "resolution comment is optional" do
        annotation = annotations(:point_annotation)

        post resolve_path(annotation), headers: auth_header(ALICE_TOKEN), as: :json

        assert_response :success
        assert_equal "Marked as resolved", response.parsed_body.dig("comment", "body")
      end

      test "resolving an already resolved annotation is idempotent" do
        annotation = annotations(:point_annotation)

        post resolve_path(annotation),
          params: { comment: "First resolution" },
          headers: auth_header(ALICE_TOKEN),
          as: :json
        assert_response :success
        original_comment_id = response.parsed_body.dig("comment", "id")

        assert_no_difference -> { annotation.annotation_comments.count } do
          post resolve_path(annotation),
            params: { comment: "Retry must not duplicate" },
            headers: auth_header(ALICE_TOKEN),
            as: :json
        end

        assert_response :success
        assert_equal "already_resolved", response.parsed_body["operation"]
        assert_equal "resolved", response.parsed_body.dig("annotation", "status")
        assert_equal original_comment_id, response.parsed_body.dig("comment", "id")
      end

      test "invalid resolution comment rolls back the status change" do
        annotation = annotations(:point_annotation)

        assert_no_difference -> { annotation.annotation_comments.count } do
          post resolve_path(annotation),
            params: { comment: "x" * 5001 },
            headers: auth_header(ALICE_TOKEN),
            as: :json
        end

        assert_response :unprocessable_entity
        assert_equal "validation_failed", response.parsed_body["code"]
        assert annotation.reload.open?
      end

      test "array resolution comment is rejected without changing the annotation" do
        annotation = annotations(:point_annotation)

        assert_no_difference -> { annotation.annotation_comments.count } do
          post resolve_path(annotation),
            params: { comment: [ "not", "a", "string" ] },
            headers: auth_header(ALICE_TOKEN),
            as: :json
        end

        assert_response :unprocessable_entity
        assert_equal "validation_failed", response.parsed_body["code"]
        assert_equal [ "Comment must be a string" ], response.parsed_body["details"]
        assert annotation.reload.open?
      end

      test "object resolution comment is rejected without changing the annotation" do
        annotation = annotations(:point_annotation)

        assert_no_difference -> { annotation.annotation_comments.count } do
          post resolve_path(annotation),
            params: { comment: { nested: "value" } },
            headers: auth_header(ALICE_TOKEN),
            as: :json
        end

        assert_response :unprocessable_entity
        assert_equal "validation_failed", response.parsed_body["code"]
        assert_equal [ "Comment must be a string" ], response.parsed_body["details"]
        assert annotation.reload.open?
      end

      test "oauth read token cannot resolve annotations" do
        annotation = annotations(:point_annotation)
        token = oauth_token(user: users(:alice), scopes: "mcp_read")

        assert_no_difference -> { annotation.annotation_comments.count } do
          post resolve_path(annotation),
            params: { project_id: projects(:alice_project).id },
            headers: auth_header(token.token),
            as: :json
        end

        assert_response :forbidden
        assert_equal "insufficient_scope", response.parsed_body["code"]
        assert annotation.reload.open?
      end

      test "oauth resolution requires explicit project context" do
        annotation = annotations(:point_annotation)
        token = oauth_token(user: users(:alice), scopes: "mcp_write")

        post resolve_path(annotation), headers: auth_header(token.token), as: :json

        assert_response :unprocessable_entity
        assert_equal "missing_project", response.parsed_body["code"]
        assert annotation.reload.open?
      end

      test "oauth token cannot resolve an annotation through a non-member project" do
        annotation = annotations(:point_annotation)
        token = oauth_token(user: users(:alice), scopes: "mcp_write")

        post resolve_path(annotation),
          params: { project_id: projects(:bob_project).id },
          headers: auth_header(token.token),
          as: :json

        assert_response :forbidden
        assert_equal "forbidden", response.parsed_body["code"]
        assert annotation.reload.open?
      end

      test "oauth token cannot resolve a known annotation outside the selected project" do
        annotation = annotations(:bob_annotation)
        token = oauth_token(user: users(:alice), scopes: "mcp_write")

        post resolve_path(annotation),
          params: { project_id: projects(:alice_project).id },
          headers: auth_header(token.token),
          as: :json

        assert_response :not_found
        assert_equal "not_found", response.parsed_body["code"]
        assert annotation.reload.open?
      end

      test "project-scoped oauth token cannot cross into another member project" do
        annotation = annotations(:point_annotation)
        user = users(:bob)
        token = oauth_token(
          user: user,
          project: projects(:bob_project),
          scopes: "mcp_write"
        )

        post resolve_path(annotation),
          params: { project_id: projects(:alice_project).id },
          headers: auth_header(token.token),
          as: :json

        assert_response :forbidden
        assert_equal "forbidden", response.parsed_body["code"]
        assert annotation.reload.open?
      end

      test "api key cannot resolve an annotation outside its project" do
        annotation = annotations(:bob_annotation)

        post resolve_path(annotation), headers: auth_header(ALICE_TOKEN), as: :json

        assert_response :not_found
        assert_equal "not_found", response.parsed_body["code"]
        assert annotation.reload.open?
      end

      private

      def resolve_path(annotation)
        "/api/v1/annotations/#{annotation.id}/resolve"
      end

      def auth_header(token)
        { "Authorization" => "Bearer #{token}" }
      end

      def oauth_token(user:, project: nil, scopes:)
        create_oauth_token(
          application: create_oauth_application,
          user: user,
          project: project,
          scopes: scopes
        )
      end
    end
  end
end
