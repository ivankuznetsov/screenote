# frozen_string_literal: true

require "test_helper"

module Api
  class ScreenshotUploadsControllerTest < ActionDispatch::IntegrationTest
    setup do
      @project = projects(:alice_project)
      @page = pages(:alice_page)
      @image_data = File.binread(Rails.root.join("test/fixtures/files/test_image.png"))
    end

    test "upload with valid token attaches image to ScreenshotImage" do
      screenshot, si, token = create_screenshot_with_upload_token

      put api_screenshot_upload_path(screenshot, token: token, mime_type: "image/png"),
        headers: { "Content-Type" => "image/png" },
        env: { "RAW_POST_DATA" => @image_data }

      assert_response :ok
      body = response.parsed_body
      assert body["success"]
      assert_equal screenshot.id, body["screenshot_id"]
      assert body["annotate_url"].present?
      assert si.reload.image.attached?, "Image should be attached to the ScreenshotImage"
      assert_not screenshot.reload.image.attached?, "Screenshot itself should NOT hold the image"
    end

    test "rejects expired token" do
      screenshot, _, token = create_screenshot_with_upload_token

      travel 6.minutes do
        put api_screenshot_upload_path(screenshot, token: token, mime_type: "image/png"),
          headers: { "Content-Type" => "image/png" },
          env: { "RAW_POST_DATA" => @image_data }

        assert_response :unauthorized
      end
    end

    test "rejects reused token after image already attached" do
      screenshot, _, token = create_screenshot_with_upload_token

      put api_screenshot_upload_path(screenshot, token: token, mime_type: "image/png"),
        headers: { "Content-Type" => "image/png" },
        env: { "RAW_POST_DATA" => @image_data }
      assert_response :ok

      put api_screenshot_upload_path(screenshot, token: token, mime_type: "image/png"),
        headers: { "Content-Type" => "image/png" },
        env: { "RAW_POST_DATA" => @image_data }
      assert_response :unauthorized
    end

    test "rejects invalid token" do
      screenshot, _, _ = create_screenshot_with_upload_token

      put api_screenshot_upload_path(screenshot, token: "bogus-token", mime_type: "image/png"),
        headers: { "Content-Type" => "image/png" },
        env: { "RAW_POST_DATA" => @image_data }

      assert_response :unauthorized
    end

    test "rejects empty body" do
      screenshot, _, token = create_screenshot_with_upload_token

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
    end

    test "rejects token issued for a ScreenshotImage on a different Screenshot (IDOR guard)" do
      mine = @page.screenshots.create!(title: "Mine")
      mine_si = mine.screenshot_images.create!(viewport: :desktop)
      mine_token = mine_si.generate_token_for(:upload)

      other = @page.screenshots.create!(title: "Other")

      # Attempting to use mine's token against other's URL must be rejected.
      put api_screenshot_upload_path(other, token: mine_token, mime_type: "image/png"),
        headers: { "Content-Type" => "image/png" },
        env: { "RAW_POST_DATA" => @image_data }

      assert_response :unauthorized
    end

    test "routes upload to the correct viewport's ScreenshotImage (multi-viewport support)" do
      screenshot = @page.screenshots.create!(title: "Multi")
      desktop = screenshot.screenshot_images.create!(viewport: :desktop)
      mobile  = screenshot.screenshot_images.create!(viewport: :mobile)
      mobile_token = mobile.generate_token_for(:upload)

      put api_screenshot_upload_path(screenshot, token: mobile_token, mime_type: "image/png"),
        headers: { "Content-Type" => "image/png" },
        env: { "RAW_POST_DATA" => @image_data }

      assert_response :ok
      assert mobile.reload.image.attached?, "Mobile variant should have the blob"
      assert_not desktop.reload.image.attached?, "Desktop variant should be untouched"
    end

    test "rejects invalid mime type" do
      screenshot, _, token = create_screenshot_with_upload_token

      put api_screenshot_upload_path(screenshot, token: token, mime_type: "text/html"),
        headers: { "Content-Type" => "text/html" },
        env: { "RAW_POST_DATA" => @image_data }

      assert_response :unprocessable_entity
      assert_match(/Invalid mime type/, response.parsed_body["error"])
    end

    test "enqueues dimension job targeting the ScreenshotImage after upload" do
      screenshot, si, token = create_screenshot_with_upload_token

      put api_screenshot_upload_path(screenshot, token: token, mime_type: "image/png"),
        headers: { "Content-Type" => "image/png" },
        env: { "RAW_POST_DATA" => @image_data }

      assert_response :ok
      assert_enqueued_with(job: ScreenshotDimensionJob, args: [ si, si.reload.image.blob.id ])
    end

    private

    # Mirrors what CreateScreenshotUploadTool does: creates Screenshot + desktop
    # ScreenshotImage, issues the token on the ScreenshotImage.
    def create_screenshot_with_upload_token
      screenshot = @page.screenshots.create!(title: "Upload test")
      si = screenshot.screenshot_images.create!(viewport: :desktop)
      token = si.generate_token_for(:upload)
      [ screenshot, si, token ]
    end
  end
end
