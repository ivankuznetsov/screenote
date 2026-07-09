# frozen_string_literal: true

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

      private

      def auth_header(token)
        { "Authorization" => "Bearer #{token}" }
      end
    end
  end
end
