# frozen_string_literal: true

require "test_helper"

module Api
  module V1
    class ScreenshotsControllerTest < ActionDispatch::IntegrationTest
      ALICE_TOKEN = "sk_proj_test_alice_key_000000000000000000000000"
      REVOKED_TOKEN = "sk_proj_test_alice_revoked_00000000000000000000"

      setup do
        @api_key = api_keys(:alice_key)
        @project = projects(:alice_project)
        @image = fixture_file_upload("test_image.png", "image/png")
      end

      test "creates screenshot with valid image and auth" do
        assert_difference "Screenshot.count", 1 do
          post api_v1_screenshots_path,
            params: { image: @image, title: "Homepage" },
            headers: auth_header(ALICE_TOKEN)
        end

        assert_response :created
        body = response.parsed_body
        assert body["screenshot_id"].present?, "Response should include screenshot_id"
        assert body["annotate_url"].present?, "Response should include annotate_url"

        screenshot = Screenshot.find(body["screenshot_id"])
        assert_equal "Homepage", screenshot.title
        assert screenshot.image.attached?, "Image should be attached"
        assert_equal @project.id, screenshot.project.id, "Screenshot should belong to the project via page"
      end

      test "returns 401 without authorization header" do
        post api_v1_screenshots_path,
          params: { image: @image, title: "Test" }

        assert_response :unauthorized
        assert_equal "Invalid or missing API key", response.parsed_body["error"]
      end

      test "returns 401 with invalid token" do
        post api_v1_screenshots_path,
          params: { image: @image, title: "Test" },
          headers: auth_header("sk_proj_bogus_token")

        assert_response :unauthorized
      end

      test "returns 401 with revoked key" do
        post api_v1_screenshots_path,
          params: { image: @image, title: "Test" },
          headers: auth_header(REVOKED_TOKEN)

        assert_response :unauthorized
      end

      test "returns 422 when image is missing" do
        post api_v1_screenshots_path,
          params: { title: "No image" },
          headers: auth_header(ALICE_TOKEN)

        assert_response :unprocessable_entity
        assert_equal "Image file is required", response.parsed_body["error"]
      end

      test "uses default title when none provided" do
        assert_difference "Screenshot.count", 1 do
          post api_v1_screenshots_path,
            params: { image: @image },
            headers: auth_header(ALICE_TOKEN)
        end

        assert_response :created
        assert_equal "Untitled", Screenshot.last.title
      end

      test "uses custom title when provided" do
        post api_v1_screenshots_path,
          params: { image: @image, title: "Login Page" },
          headers: auth_header(ALICE_TOKEN)

        assert_response :created
        assert_equal "Login Page", Screenshot.last.title
      end

      test "touches last_used_at on the api key" do
        @api_key.update_column(:last_used_at, 1.hour.ago)
        old_last_used = @api_key.last_used_at

        post api_v1_screenshots_path,
          params: { image: @image, title: "Touch test" },
          headers: auth_header(ALICE_TOKEN)

        assert_response :created
        assert @api_key.reload.last_used_at > old_last_used, "last_used_at should be updated"
      end

      private

      def auth_header(token)
        { "Authorization" => "Bearer #{token}" }
      end
    end
  end
end
