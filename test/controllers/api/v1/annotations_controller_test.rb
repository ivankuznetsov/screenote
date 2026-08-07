# frozen_string_literal: true

# screenote-edition: self_hosted

require "test_helper"

module Api
  module V1
    class AnnotationsControllerTest < ActionDispatch::IntegrationTest
      ALICE_TOKEN = "sk_proj_test_alice_key_000000000000000000000000"

      setup do
        @project = projects(:alice_project)
        @screenshot = screenshots(:alice_screenshot)
      end

      test "lists annotations for a screenshot" do
        get api_v1_screenshot_annotations_path(@screenshot),
          headers: auth_header(ALICE_TOKEN)

        assert_response :success
        body = response.parsed_body
        assert body["annotations"].is_a?(Array), "Response should include annotations array"
        assert body["pagination"].present?, "Response should include pagination"
      end

      test "filters annotations by status" do
        get api_v1_screenshot_annotations_path(@screenshot, status: "open"),
          headers: auth_header(ALICE_TOKEN)

        assert_response :success
        body = response.parsed_body
        body["annotations"].each do |annotation|
          assert_equal "open", annotation["status"], "All annotations should be open"
        end
      end

      test "filters annotations by viewport and paginates" do
        get api_v1_screenshot_annotations_path(@screenshot, viewport: "desktop", limit: 2, offset: 0),
          headers: auth_header(ALICE_TOKEN)

        assert_response :success
        body = response.parsed_body
        assert_equal 2, body["pagination"]["limit"]
        body["annotations"].each do |annotation|
          assert_equal "desktop", annotation["viewport"]
        end
      end

      test "does not list annotations for another project screenshot" do
        # The screenshot must actually own annotations, otherwise an empty result
        # proves nothing about cross-project scoping.
        assert screenshots(:bob_screenshot).annotations.any?

        get api_v1_screenshot_annotations_path(screenshots(:bob_screenshot)),
          headers: auth_header(ALICE_TOKEN)

        assert_response :success
        assert_empty response.parsed_body["annotations"]
      end

      test "gets annotation details with comments" do
        get api_v1_annotation_path(annotations(:resolved_annotation)),
          headers: auth_header(ALICE_TOKEN)

        assert_response :success
        body = response.parsed_body
        assert_equal annotations(:resolved_annotation).id, body["id"]
        assert_equal "ready", body["screenshot_status"]
        assert_equal "image/png", body["mime_type"]
        assert body["comments"].any? { |comment| comment["body"] == "Fixed the alignment issue" }
      end

      test "crop failures are monitored and return annotation details without a private crop" do
        error = StandardError.new("crop unavailable")
        notifications = []
        original = Annotation.instance_method(:crop)
        original_notify = Screenote::Monitoring.method(:notify)
        Annotation.define_method(:crop) { raise error }
        Screenote::Monitoring.define_singleton_method(:notify) do |raised, context:|
          notifications << [ raised, context ]
        end

        get api_v1_annotation_path(annotations(:resolved_annotation)),
          headers: auth_header(ALICE_TOKEN)

        assert_response :success
        assert_nil response.parsed_body["cropped_image_base64"]
        assert_equal error, notifications.dig(0, 0)
        assert_equal annotations(:resolved_annotation).id, notifications.dig(0, 1, :annotation_id)
        assert_equal annotations(:resolved_annotation).screenshot_id, notifications.dig(0, 1, :screenshot_id)
        assert_equal annotations(:resolved_annotation).viewport, notifications.dig(0, 1, :viewport)
      ensure
        Annotation.define_method(:crop, original) if original
        Screenote::Monitoring.define_singleton_method(:notify, original_notify) if original_notify
      end

      test "does not get annotation outside the key project" do
        get api_v1_annotation_path(annotations(:bob_annotation)),
          headers: auth_header(ALICE_TOKEN)

        assert_response :not_found
        assert_equal "not_found", response.parsed_body["code"]
      end

      test "returns 401 without authorization" do
        get api_v1_screenshot_annotations_path(@screenshot)

        assert_response :unauthorized
      end

      test "oauth read token lists annotations with explicit project" do
        token = oauth_token(user: users(:alice), scopes: "mcp_read")

        get api_v1_screenshot_annotations_path(@screenshot, project_id: @project.id),
          headers: auth_header(token.token)

        assert_response :success
        assert response.parsed_body["annotations"].is_a?(Array)
      end

      test "oauth annotation list requires explicit project" do
        token = oauth_token(user: users(:alice), scopes: "mcp_read")

        get api_v1_screenshot_annotations_path(@screenshot), headers: auth_header(token.token)

        assert_response :unprocessable_entity
        assert_equal "missing_project", response.parsed_body["code"]
      end

      test "oauth write-only token cannot list annotations" do
        token = oauth_token(user: users(:alice), scopes: "mcp_write")

        get api_v1_screenshot_annotations_path(@screenshot, project_id: @project.id),
          headers: auth_header(token.token)

        assert_response :forbidden
        assert_equal "insufficient_scope", response.parsed_body["code"]
      end

      test "oauth read token gets annotation details with explicit project" do
        token = oauth_token(user: users(:alice), scopes: "mcp_read")

        get api_v1_annotation_path(annotations(:resolved_annotation), project_id: @project.id),
          headers: auth_header(token.token)

        assert_response :success
        assert_equal annotations(:resolved_annotation).id, response.parsed_body["id"]
      end

      test "annotation details fail closed if project authority disappears after authentication" do
        token = oauth_token(user: users(:alice), scopes: "mcp_read")
        original = Api::V1::ProjectScope.method(:resolve_project)
        Api::V1::ProjectScope.define_singleton_method(:resolve_project) { |*, **| nil }

        get api_v1_annotation_path(annotations(:resolved_annotation), project_id: @project.id),
          headers: auth_header(token.token)

        assert_response :forbidden
        assert_equal "forbidden", response.parsed_body["code"]
      ensure
        Api::V1::ProjectScope.define_singleton_method(:resolve_project, original) if original
      end

      test "oauth token cannot get annotation outside member project by known id" do
        token = oauth_token(user: users(:alice), scopes: "mcp_read")

        get api_v1_annotation_path(annotations(:bob_annotation), project_id: @project.id),
          headers: auth_header(token.token)

        assert_response :not_found
      end

      test "oauth write-only token cannot read annotations" do
        token = oauth_token(user: users(:alice), scopes: "mcp_write")

        get api_v1_annotation_path(annotations(:resolved_annotation), project_id: @project.id),
          headers: auth_header(token.token)

        assert_response :forbidden
        assert_equal "insufficient_scope", response.parsed_body["code"]
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
