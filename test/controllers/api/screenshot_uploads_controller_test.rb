# frozen_string_literal: true

require "test_helper"

module Api
  class ScreenshotUploadsControllerTest < ActionDispatch::IntegrationTest
    setup do
      @project = projects(:alice_project)
      @image_data = File.binread(Rails.root.join("test/fixtures/files/test_image.png"))
    end

    test "upload with valid token attaches image" do
      screenshot = @project.screenshots.create!(title: "Upload test")
      token = screenshot.generate_token_for(:upload)

      put api_screenshot_upload_path(screenshot, token: token, mime_type: "image/png"),
        headers: { "Content-Type" => "image/png" },
        env: { "RAW_POST_DATA" => @image_data }

      assert_response :ok
      body = response.parsed_body
      assert body["success"], "Should return success"
      assert_equal screenshot.id, body["screenshot_id"]
      assert body["annotate_url"].present?, "Should return annotate URL"
      assert screenshot.reload.image.attached?, "Image should be attached"
    end

    test "rejects expired token" do
      screenshot = @project.screenshots.create!(title: "Expired token")
      token = screenshot.generate_token_for(:upload)

      travel 6.minutes do
        put api_screenshot_upload_path(screenshot, token: token, mime_type: "image/png"),
          headers: { "Content-Type" => "image/png" },
          env: { "RAW_POST_DATA" => @image_data }

        assert_response :unauthorized
        assert_equal "Invalid or expired upload token", response.parsed_body["error"]
      end
    end

    test "rejects reused token after image already attached" do
      screenshot = @project.screenshots.create!(title: "Reuse test")
      token = screenshot.generate_token_for(:upload)

      # First upload succeeds
      put api_screenshot_upload_path(screenshot, token: token, mime_type: "image/png"),
        headers: { "Content-Type" => "image/png" },
        env: { "RAW_POST_DATA" => @image_data }
      assert_response :ok

      # Second upload with same token fails (token invalidated by image attach)
      put api_screenshot_upload_path(screenshot, token: token, mime_type: "image/png"),
        headers: { "Content-Type" => "image/png" },
        env: { "RAW_POST_DATA" => @image_data }
      assert_response :unauthorized
    end

    test "rejects invalid token" do
      screenshot = @project.screenshots.create!(title: "Invalid token")

      put api_screenshot_upload_path(screenshot, token: "bogus-token", mime_type: "image/png"),
        headers: { "Content-Type" => "image/png" },
        env: { "RAW_POST_DATA" => @image_data }

      assert_response :unauthorized
      assert_equal "Invalid or expired upload token", response.parsed_body["error"]
    end

    test "rejects empty body" do
      screenshot = @project.screenshots.create!(title: "Empty body")
      token = screenshot.generate_token_for(:upload)

      put api_screenshot_upload_path(screenshot, token: token, mime_type: "image/png"),
        headers: { "Content-Type" => "image/png" }

      assert_response :unprocessable_entity
      assert_equal "Request body is empty", response.parsed_body["error"]
    end

    test "rejects non-existent screenshot" do
      put api_screenshot_upload_path(id: 999999, token: "any", mime_type: "image/png"),
        headers: { "Content-Type" => "image/png" },
        env: { "RAW_POST_DATA" => @image_data }

      assert_response :not_found
      assert_equal "Screenshot not found", response.parsed_body["error"]
    end

    test "rejects invalid mime type" do
      screenshot = @project.screenshots.create!(title: "Bad MIME")
      token = screenshot.generate_token_for(:upload)

      put api_screenshot_upload_path(screenshot, token: token, mime_type: "text/html"),
        headers: { "Content-Type" => "text/html" },
        env: { "RAW_POST_DATA" => @image_data }

      assert_response :unprocessable_entity
      assert_match(/Invalid mime type/, response.parsed_body["error"])
    end

    test "enqueues dimension job after upload" do
      screenshot = @project.screenshots.create!(title: "Dimension job")
      token = screenshot.generate_token_for(:upload)

      assert_enqueued_with(job: ScreenshotDimensionJob) do
        put api_screenshot_upload_path(screenshot, token: token, mime_type: "image/png"),
          headers: { "Content-Type" => "image/png" },
          env: { "RAW_POST_DATA" => @image_data }
      end

      assert_response :ok
    end
  end
end
