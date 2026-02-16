# frozen_string_literal: true

require_relative "application_system_test_case"
require_relative "pages/auth_page"
require_relative "pages/projects_page"
require_relative "pages/api_keys_page"

require "net/http"
require "json"

class ApiUploadTest < ApplicationSystemTestCase
  include Pages::AuthPage
  include Pages::ProjectsPage
  include Pages::ApiKeysPage

  setup do
    login_as_test_user
  end

  test "upload screenshot via API and verify it appears in project" do
    token = create_api_key("Demo Project", "Upload E2E #{Time.now.to_i}")
    screenshot_title = "API Upload #{Time.now.to_i}"

    response = api_upload_screenshot(token: token, image_path: TEST_IMAGE_PATH, title: screenshot_title)
    assert_equal 201, response.code.to_i, "Expected 201 Created but got #{response.code}: #{response.body}"

    navigate_to_demo_project

    assert_selector '[data-testid="screenshot-card-title"]', text: screenshot_title, wait: 10
  end

  test "API returns correct JSON response with annotate_url" do
    token = create_api_key("Demo Project", "JSON E2E #{Time.now.to_i}")

    response = api_upload_screenshot(token: token, image_path: TEST_IMAGE_PATH, title: "JSON Test #{Time.now.to_i}")
    assert_equal 201, response.code.to_i, "Expected 201 Created"

    body = JSON.parse(response.body)
    assert body["screenshot_id"].present?, "Response should include screenshot_id"
    assert body["annotate_url"].present?, "Response should include annotate_url"

    visit body["annotate_url"]
    assert_selector '[data-testid="screenshot-workspace"]', wait: 10
  end

  test "API rejects request without auth" do
    response = api_upload_screenshot(token: nil, image_path: TEST_IMAGE_PATH)
    assert_equal 401, response.code.to_i, "Expected 401 Unauthorized without auth header"

    body = JSON.parse(response.body)
    assert body["error"].present?, "Response should include an error message"
  end

  test "API rejects request without image" do
    token = create_api_key("Demo Project", "No Image E2E #{Time.now.to_i}")

    response = api_upload_screenshot(token: token, image_path: nil)
    assert_equal 422, response.code.to_i, "Expected 422 Unprocessable Entity without image"

    body = JSON.parse(response.body)
    assert body["error"].present?, "Response should include an error message"
  end

  test "revoked API key is rejected" do
    key_name = "Revoke E2E #{Time.now.to_i}"
    token = create_api_key("Demo Project", key_name)

    # Verify the token works before revoking
    response = api_upload_screenshot(token: token, image_path: TEST_IMAGE_PATH, title: "Before Revoke")
    assert_equal 201, response.code.to_i, "Token should work before revoking"

    # Revoke via UI
    visit_api_keys("Demo Project")
    revoke_api_key(key_name)

    # Verify the revoked token is rejected
    response = api_upload_screenshot(token: token, image_path: TEST_IMAGE_PATH, title: "After Revoke")
    assert_equal 401, response.code.to_i, "Revoked token should be rejected with 401"
  end

  private

  def api_upload_screenshot(token:, image_path:, title: nil)
    uri = URI("#{Capybara.app_host}/api/v1/screenshots")

    request = Net::HTTP::Post.new(uri)
    request["Authorization"] = "Bearer #{token}" if token

    if image_path
      boundary = "----RubyMultipartBoundary#{SecureRandom.hex(16)}"
      request["Content-Type"] = "multipart/form-data; boundary=#{boundary}"
      request.body = build_multipart_body(boundary, image_path, title)
    end

    Net::HTTP.start(uri.hostname, uri.port) do |http|
      http.request(request)
    end
  end

  def build_multipart_body(boundary, image_path, title)
    parts = []

    if title
      parts << "--#{boundary}\r\n" \
               "Content-Disposition: form-data; name=\"title\"\r\n\r\n" \
               "#{title}\r\n"
    end

    image_data = File.binread(image_path)
    filename = File.basename(image_path)
    parts << "--#{boundary}\r\n" \
             "Content-Disposition: form-data; name=\"image\"; filename=\"#{filename}\"\r\n" \
             "Content-Type: image/png\r\n\r\n" \
             "#{image_data}\r\n"

    parts << "--#{boundary}--\r\n"
    parts.join
  end
end
