# frozen_string_literal: true

# screenote-edition: self_hosted

require "test_helper"

module Api
  module V1
    class SnapshotsControllerTest < ActionDispatch::IntegrationTest
      ALICE_TOKEN = "sk_proj_test_alice_key_000000000000000000000000"
      REVOKED_TOKEN = "sk_proj_test_alice_revoked_00000000000000000000"
      BOB_TOKEN = "sk_proj_test_bob_key_0000000000000000000000000"

      setup do
        @project = projects(:alice_project)
        @payload = snapshot_manifest_payload
      end

      test "prepares and recovers an identical snapshot contract" do
        post api_v1_project_snapshots_path(@project), params: @payload, headers: auth_header(ALICE_TOKEN), as: :json

        assert_response :created
        created = response.parsed_body
        assert_equal "created", created["operation"]
        assert_equal "awaiting_upload", created["state"]
        assert_equal 3, created["entries"].length
        assert_match(/snapshot_id=#{created.fetch('snapshot_id')}/, created["review_url"])

        assert_no_difference [ "Snapshot.count", "Screenshot.count", "ScreenshotImage.count" ] do
          post api_v1_project_snapshots_path(@project), params: @payload, headers: auth_header(ALICE_TOKEN), as: :json
        end

        assert_response :success
        replay = response.parsed_body
        assert_equal "resumed", replay["operation"]
        assert_equal created["snapshot_id"], replay["snapshot_id"]
        assert_equal created["entries"].map { |entry| entry["image_id"] }, replay["entries"].map { |entry| entry["image_id"] }
      end

      test "show returns the recoverable graph" do
        snapshot = Snapshots::PrepareUpload.call(project: @project, payload: @payload).snapshot

        get api_v1_project_snapshot_path(@project, snapshot), headers: auth_header(ALICE_TOKEN)

        assert_response :success
        assert_equal snapshot.id, response.parsed_body["snapshot_id"]
        assert_equal "status", response.parsed_body["operation"]
        assert_equal "awaiting_upload", response.parsed_body["state"]
      end

      test "invalid digest returns structured validation error with zero mutation" do
        assert_no_difference [ "Snapshot.count", "Screenshot.count", "ScreenshotImage.count", "Page.count" ] do
          post api_v1_project_snapshots_path(@project),
            params: @payload.merge(manifest_digest: "0" * 64),
            headers: auth_header(ALICE_TOKEN),
            as: :json
        end

        assert_response :unprocessable_entity
        assert_equal "invalid_manifest", response.parsed_body["code"]
      end

      test "requires write scope to prepare and read scope to show" do
        read_token = oauth_token(user: users(:alice), scopes: "mcp_read")
        write_token = oauth_token(user: users(:alice), scopes: "mcp_write")

        post api_v1_project_snapshots_path(@project), params: @payload,
          headers: auth_header(read_token.token), as: :json
        assert_response :forbidden
        assert_equal "insufficient_scope", response.parsed_body["code"]

        post api_v1_project_snapshots_path(@project), params: @payload,
          headers: auth_header(write_token.token), as: :json
        assert_response :created
        snapshot_id = response.parsed_body["snapshot_id"]

        get api_v1_project_snapshot_path(@project, snapshot_id), headers: auth_header(write_token.token)
        assert_response :forbidden
        assert_equal "insufficient_scope", response.parsed_body["code"]

        get api_v1_project_snapshot_path(@project, snapshot_id), headers: auth_header(read_token.token)
        assert_response :success
      end

      test "rejects missing revoked and cross-project credentials" do
        post api_v1_project_snapshots_path(@project), params: @payload, as: :json
        assert_response :unauthorized

        post api_v1_project_snapshots_path(@project), params: @payload,
          headers: auth_header(REVOKED_TOKEN), as: :json
        assert_response :unauthorized

        post api_v1_project_snapshots_path(projects(:bob_project)), params: @payload,
          headers: auth_header(ALICE_TOKEN), as: :json
        assert_response :forbidden
      end

      test "does not expose another project's snapshot" do
        snapshot = Snapshots::PrepareUpload.call(project: @project, payload: @payload).snapshot

        get api_v1_project_snapshot_path(projects(:bob_project), snapshot),
          headers: auth_header(BOB_TOKEN)

        assert_response :not_found
      end

      private

      def auth_header(token)
        { "Authorization" => "Bearer #{token}" }
      end

      def oauth_token(user:, scopes:)
        create_oauth_token(application: create_oauth_application, user: user, scopes: scopes)
      end
    end
  end
end
