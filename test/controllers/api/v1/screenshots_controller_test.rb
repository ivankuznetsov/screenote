# frozen_string_literal: true

# screenote-edition: self_hosted

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

      test "lists screenshots with filters and pagination" do
        get api_v1_project_screenshots_path(@project, page_id: pages(:alice_page).id, status: "ready", limit: 1, offset: 0),
          headers: auth_header(ALICE_TOKEN)

        assert_response :success
        body = response.parsed_body
        assert_equal 1, body["screenshots"].length
        assert_equal screenshots(:alice_screenshot).id, body["screenshots"].first["id"]
        assert_equal "ready", body["screenshots"].first["status"]
        assert_equal 1, body["pagination"]["limit"]
        assert_equal 1, body["pagination"]["total"]
      end

      test "does not list screenshots outside the key project" do
        get api_v1_project_screenshots_path(projects(:bob_project)),
          headers: auth_header(ALICE_TOKEN)

        assert_response :forbidden
        assert_equal "forbidden", response.parsed_body["code"]
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
        assert_equal @project.pages.find_by(name: "Homepage").id, body["page_id"]
        assert body["image"].present?, "Response should include image metadata"

        screenshot = Screenshot.find(body["screenshot_id"])
        assert_equal "Homepage", screenshot.title
        assert screenshot.primary_image.image.attached?, "Image should be attached to the desktop ScreenshotImage"
        assert_equal @project.id, screenshot.project.id, "Screenshot should belong to the project via page"
      end

      test "creates screenshot on the requested page id" do
        page = pages(:alice_page)

        post api_v1_screenshots_path,
          params: { image: @image, title: "Requested Page", page_id: page.id },
          headers: auth_header(ALICE_TOKEN)

        assert_response :created
        assert_equal page.id, Screenshot.find(response.parsed_body["screenshot_id"]).page_id
      end

      test "creates screenshot on the requested page name" do
        post api_v1_screenshots_path,
          params: { image: @image, title: "Upload Title", page: "Checkout" },
          headers: auth_header(ALICE_TOKEN)

        assert_response :created
        screenshot = Screenshot.find(response.parsed_body["screenshot_id"])
        assert_equal "Checkout", screenshot.page.name
      end

      test "returns 401 without authorization header" do
        post api_v1_screenshots_path,
          params: { image: @image, title: "Test" }

        assert_response :unauthorized
        assert_equal "Invalid or missing bearer token", response.parsed_body["error"]
        assert_equal "unauthorized", response.parsed_body["code"]
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
        assert_equal "validation_failed", response.parsed_body["code"]
      end

      test "returns 422 when image is not an uploaded file" do
        post api_v1_screenshots_path,
          params: { image: "not-a-file", title: "Bad image" },
          headers: auth_header(ALICE_TOKEN)

        assert_response :unprocessable_entity
        assert_equal "Image file is required", response.parsed_body["error"]
        assert_equal "validation_failed", response.parsed_body["code"]
      end

      test "returns stable JSON for malformed pagination params" do
        get api_v1_project_screenshots_path(@project, limit: { x: 1 }),
          headers: auth_header(ALICE_TOKEN)

        assert_response :success
        assert_equal 50, response.parsed_body["pagination"]["limit"]
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

      test "oauth read token can list screenshots for a member project" do
        token = oauth_token(user: users(:alice), scopes: "mcp_read")

        get api_v1_project_screenshots_path(@project), headers: auth_header(token.token)

        assert_response :success
        assert_includes response.parsed_body["screenshots"].map { |screenshot| screenshot["id"] }, screenshots(:alice_screenshot).id
      end

      test "oauth read token cannot create screenshots" do
        token = oauth_token(user: users(:alice), scopes: "mcp_read")

        assert_no_difference "Screenshot.count" do
          post api_v1_screenshots_path,
            params: { image: @image, title: "No write", project_id: @project.id },
            headers: auth_header(token.token)
        end

        assert_response :forbidden
        assert_equal "insufficient_scope", response.parsed_body["code"]
      end

      test "oauth write token creates screenshots for member project with explicit project" do
        token = oauth_token(user: users(:alice), scopes: "mcp_write")

        assert_difference "Screenshot.count", 1 do
          post api_v1_screenshots_path,
            params: { image: @image, title: "OAuth Upload", project_id: @project.id },
            headers: auth_header(token.token)
        end

        assert_response :created
        assert_equal @project.id, Screenshot.find(response.parsed_body["screenshot_id"]).project.id
      end

      test "oauth project scoped create requires explicit project" do
        token = oauth_token(user: users(:alice), scopes: "mcp_write")

        assert_no_difference "Screenshot.count" do
          post api_v1_screenshots_path,
            params: { image: @image, title: "Missing project" },
            headers: auth_header(token.token)
        end

        assert_response :unprocessable_entity
        assert_equal "missing_project", response.parsed_body["code"]
      end

      test "oauth token cannot access non-member project" do
        token = oauth_token(user: users(:alice), scopes: "mcp_read")

        get api_v1_project_screenshots_path(projects(:bob_project)), headers: auth_header(token.token)

        assert_response :forbidden
        assert_equal "forbidden", response.parsed_body["code"]
      end

      test "oauth write token cannot create screenshots in a non-member project" do
        token = oauth_token(user: users(:alice), scopes: "mcp_write")

        assert_no_difference "Screenshot.count" do
          post api_v1_screenshots_path,
            params: { image: @image, title: "Trespass", project_id: projects(:bob_project).id },
            headers: auth_header(token.token)
        end

        assert_response :forbidden
        assert_equal "forbidden", response.parsed_body["code"]
      end

      test "oauth requests do not touch api key last_used_at" do
        @api_key.update_column(:last_used_at, 1.hour.ago)
        old_last_used = @api_key.last_used_at
        token = oauth_token(user: users(:alice), scopes: "mcp_read")

        get api_v1_project_screenshots_path(@project), headers: auth_header(token.token)

        assert_response :success
        assert_equal old_last_used.to_i, @api_key.reload.last_used_at.to_i
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
