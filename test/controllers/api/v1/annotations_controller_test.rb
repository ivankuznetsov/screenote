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
