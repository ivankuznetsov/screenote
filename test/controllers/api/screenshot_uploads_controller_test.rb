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

      put api_screenshot_upload_path(screenshot),
        headers: upload_headers(token),
        env: { "RAW_POST_DATA" => @image_data }

      assert_response :ok
      body = response.parsed_body
      assert body["success"]
      assert_equal screenshot.id, body["screenshot_id"]
      assert body["annotate_url"].present?
      assert si.reload.image.attached?, "Image should be attached to the ScreenshotImage"
      assert_not screenshot.reload.image.attached?, "Screenshot itself should NOT hold the image"
    end

    test "defaults a missing content type to PNG" do
      screenshot, image, token = create_screenshot_with_upload_token

      rack_response = Rack::MockRequest.new(Rails.application).put(
        api_screenshot_upload_path(screenshot),
        input: @image_data,
        "HTTP_AUTHORIZATION" => "Bearer #{token}"
      )

      assert_equal 200, rack_response.status, rack_response.body
      assert_equal "image/png", image.reload.image.blob.content_type
    end

    test "rejects expired token" do
      screenshot, _, token = create_screenshot_with_upload_token

      travel 6.minutes do
        put api_screenshot_upload_path(screenshot),
          headers: upload_headers(token),
          env: { "RAW_POST_DATA" => @image_data }

        assert_response :unauthorized
      end
    end

    test "rejects reused token after image already attached" do
      screenshot, _, token = create_screenshot_with_upload_token

      put api_screenshot_upload_path(screenshot),
        headers: upload_headers(token),
        env: { "RAW_POST_DATA" => @image_data }
      assert_response :ok

      put api_screenshot_upload_path(screenshot),
        headers: upload_headers(token),
        env: { "RAW_POST_DATA" => @image_data }
      assert_response :unauthorized
    end

    test "rejects invalid token" do
      screenshot, _, _ = create_screenshot_with_upload_token

      put api_screenshot_upload_path(screenshot),
        headers: upload_headers("bogus-token"),
        env: { "RAW_POST_DATA" => @image_data }

      assert_response :unauthorized
    end

    test "rejects a credential in the query string even when it is valid" do
      screenshot, si, token = create_screenshot_with_upload_token

      put api_screenshot_upload_path(screenshot, token: token),
        headers: { "Content-Type" => "image/png" },
        env: { "RAW_POST_DATA" => @image_data }

      assert_response :unprocessable_entity
      assert_equal "credential_in_url", response.parsed_body["code"]
      assert_not si.reload.image.attached?
    end

    test "requires the exact Bearer authorization scheme" do
      screenshot, si, token = create_screenshot_with_upload_token

      put api_screenshot_upload_path(screenshot),
        headers: {
          "Authorization" => "Token #{token}",
          "Content-Type" => "image/png"
        },
        env: { "RAW_POST_DATA" => @image_data }

      assert_response :unauthorized
      assert_not si.reload.image.attached?
    end

    test "rejects missing malformed and non ASCII bearer credentials" do
      screenshot, si, _token = create_screenshot_with_upload_token

      [ nil, "Bearer", "Bearer café", "Bearer token with-space" ].each do |authorization|
        headers = { "Content-Type" => "image/png" }
        headers["Authorization"] = authorization if authorization
        put api_screenshot_upload_path(screenshot),
          headers: headers,
          env: { "RAW_POST_DATA" => @image_data }

        assert_response :unauthorized
      end

      assert_not si.reload.image.attached?
    end

    test "maps persistence validation and uniqueness failures without leaking exceptions" do
      screenshot, image, token = create_screenshot_with_upload_token
      image.errors.add(:image, "is invalid")

      with_attach_image_error(ActiveRecord::RecordInvalid.new(image)) do
        put api_screenshot_upload_path(screenshot),
          headers: upload_headers(token),
          env: { "RAW_POST_DATA" => @image_data }
      end
      assert_response :unprocessable_entity
      assert_match(/invalid/, response.parsed_body.fetch("error"))

      with_attach_image_error(ActiveRecord::RecordNotUnique.new("duplicate")) do
        put api_screenshot_upload_path(screenshot),
          headers: upload_headers(token),
          env: { "RAW_POST_DATA" => @image_data }
      end
      assert_response :conflict
      assert_equal "Image already uploaded", response.parsed_body.fetch("error")
    end

    test "rejects empty body" do
      screenshot, _, token = create_screenshot_with_upload_token

      put api_screenshot_upload_path(screenshot), headers: upload_headers(token)

      assert_response :unprocessable_entity
      assert_equal "Request body is empty", response.parsed_body["error"]
    end

    test "does not reveal whether a screenshot exists to an invalid credential" do
      put api_screenshot_upload_path(id: 999999),
        headers: upload_headers("any"),
        env: { "RAW_POST_DATA" => @image_data }

      assert_response :unauthorized
    end

    test "rejects token issued for a ScreenshotImage on a different Screenshot (IDOR guard)" do
      mine = @page.screenshots.create!(title: "Mine")
      mine_si = mine.screenshot_images.create!(viewport: :desktop)
      mine_token = mine_si.generate_token_for(:upload)

      other = @page.screenshots.create!(title: "Other")

      # Attempting to use mine's token against other's URL must be rejected.
      put api_screenshot_upload_path(other),
        headers: upload_headers(mine_token),
        env: { "RAW_POST_DATA" => @image_data }

      assert_response :unauthorized
    end

    test "routes upload to the correct viewport's ScreenshotImage (multi-viewport support)" do
      screenshot = @page.screenshots.create!(title: "Multi")
      desktop = screenshot.screenshot_images.create!(viewport: :desktop)
      mobile  = screenshot.screenshot_images.create!(viewport: :mobile)
      mobile_token = mobile.generate_token_for(:upload)

      put api_screenshot_upload_path(screenshot),
        headers: upload_headers(mobile_token),
        env: { "RAW_POST_DATA" => @image_data }

      assert_response :ok
      assert mobile.reload.image.attached?, "Mobile variant should have the blob"
      assert_not desktop.reload.image.attached?, "Desktop variant should be untouched"
    end

    test "rejects invalid mime type" do
      screenshot, _, token = create_screenshot_with_upload_token

      put api_screenshot_upload_path(screenshot),
        headers: upload_headers(token, content_type: "text/html"),
        env: { "RAW_POST_DATA" => @image_data }

      assert_response :unprocessable_entity
      assert_match(/Invalid mime type/, response.parsed_body["error"])
    end

    test "rejects an unsupported JSON body before parsing request parameters" do
      put api_screenshot_upload_path(id: 999_999),
        headers: upload_headers("missing", content_type: "application/json"),
        env: { "RAW_POST_DATA" => "{" }

      assert_response :unprocessable_entity
      assert_equal "invalid_content_type", response.parsed_body["code"]
    end

    test "rejects an anonymous oversized JSON body before parsing request parameters" do
      put api_screenshot_upload_path(id: 999_999),
        headers: upload_headers(
          "missing",
          content_type: "application/json",
          content_length: ScreenshotImage::MAX_FILE_SIZE + 1
        ),
        env: { "RAW_POST_DATA" => "{" }

      assert_response :unprocessable_entity
      assert_equal "file_too_large", response.parsed_body["code"]
    end

    test "rejects bytes that do not match the declared image type" do
      screenshot, si, token = create_screenshot_with_upload_token

      put api_screenshot_upload_path(screenshot),
        headers: upload_headers(token),
        env: { "RAW_POST_DATA" => "not an image" }

      assert_response :unprocessable_entity
      assert_match(/valid PNG or JPEG/, response.parsed_body["error"])
      assert_not si.reload.image.attached?
    end

    test "rejects an image whose dimensions exceed the decoder boundary" do
      require_vips!
      screenshot, si, token = create_screenshot_with_upload_token
      oversized_dimensions = Vips::Image.black(ScreenshotImage::MAX_DIMENSION + 1, 1).pngsave_buffer

      put api_screenshot_upload_path(screenshot),
        headers: upload_headers(token),
        env: { "RAW_POST_DATA" => oversized_dimensions }

      assert_response :unprocessable_entity
      assert_match(/dimensions/, response.parsed_body["error"])
      assert_not si.reload.image.attached?
    end

    test "rejects an image whose decoded pixel count exceeds the boundary" do
      screenshot, si, token = create_screenshot_with_upload_token
      oversized_pixels = png_header(width: 10_000, height: 5_001)

      put api_screenshot_upload_path(screenshot),
        headers: upload_headers(token),
        env: { "RAW_POST_DATA" => oversized_pixels }

      assert_response :unprocessable_entity
      assert_match(/pixel count/, response.parsed_body["error"])
      assert_not si.reload.image.attached?
    end

    test "enqueues dimension job targeting the ScreenshotImage after upload" do
      screenshot, si, token = create_screenshot_with_upload_token

      put api_screenshot_upload_path(screenshot),
        headers: upload_headers(token),
        env: { "RAW_POST_DATA" => @image_data }

      assert_response :ok
      assert_enqueued_with(job: ScreenshotDimensionJob, args: [ si, si.reload.image.blob.id ])
    end

    private

    def upload_headers(token, content_type: "image/png", content_length: nil)
      {
        "Authorization" => "Bearer #{token}",
        "Content-Type" => content_type
      }.tap do |headers|
        headers["Content-Length"] = content_length.to_s if content_length
      end
    end

    # Mirrors what CreateScreenshotUploadTool does: creates Screenshot + desktop
    # ScreenshotImage, issues the token on the ScreenshotImage.
    def create_screenshot_with_upload_token
      screenshot = @page.screenshots.create!(title: "Upload test")
      si = screenshot.screenshot_images.create!(viewport: :desktop)
      token = si.generate_token_for(:upload)
      [ screenshot, si, token ]
    end

    def with_attach_image_error(error)
      original = Snapshots::AttachImage.method(:call)
      Snapshots::AttachImage.define_singleton_method(:call) { |**| raise error }
      yield
    ensure
      Snapshots::AttachImage.define_singleton_method(:call, original) if original
    end

    def png_header(width:, height:)
      signature = "\x89PNG\r\n\x1a\n".b
      ihdr = [ width, height, 8, 0, 0, 0, 0 ].pack("NNCCCCC")
      signature + png_chunk("IHDR", ihdr) + png_chunk("IDAT", Zlib::Deflate.deflate("")) + png_chunk("IEND", "")
    end

    def png_chunk(type, data)
      [ data.bytesize ].pack("N") + type + data + [ Zlib.crc32(type + data) ].pack("N")
    end
  end
end
