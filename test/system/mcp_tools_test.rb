# frozen_string_literal: true

require_relative "application_system_test_case"
require_relative "pages/auth_page"
require_relative "pages/projects_page"
require_relative "pages/api_keys_page"
require_relative "pages/pages_page"
require_relative "pages/screenshots_page"
require_relative "pages/annotations_page"

require "net/http"
require "json"
require "base64"

class McpToolsTest < ApplicationSystemTestCase
  include Pages::AuthPage
  include Pages::ProjectsPage
  include Pages::ApiKeysPage
  include Pages::PagesPage
  include Pages::ScreenshotsPage
  include Pages::AnnotationsPage

  setup do
    login_as_test_user
  end

  test "create_screenshot via MCP and verify in UI" do
    token, project_id = create_api_key_with_project("Demo Project", "MCP Create #{Time.now.to_i}")
    title = "MCP Screenshot #{Time.now.to_i}"

    result = mcp_create_screenshot(token, project_id, title)

    assert result["screenshot_id"].present?, "Response should include screenshot_id"
    assert result["annotate_url"].present?, "Response should include annotate_url"

    # MCP creates a page from the title — navigate to the project and then the page
    navigate_to_demo_project
    click_page(title)
    assert_on_page_show(title)
    assert_selector SELECTED_VERSION_TITLE, minimum: 1, wait: 10
  end

  test "list_screenshots returns project screenshots" do
    token, project_id = create_api_key_with_project("Demo Project", "MCP List #{Time.now.to_i}")
    title = "MCP Listed #{Time.now.to_i}"

    mcp_create_screenshot(token, project_id, title)

    response = call_mcp_tool(token: token, tool_name: "list_screenshots", arguments: { project_id: project_id })
    assert_equal "200", response.code, "list_screenshots should return 200"

    result = parse_mcp_result(response)
    screenshots = result["screenshots"]

    assert screenshots.is_a?(Array), "Response should contain screenshots array"
    match = screenshots.find { |s| s["title"] == title }
    assert match.present?, "Uploaded screenshot '#{title}' should appear in list"
    assert_equal 0, match["annotation_count"], "New screenshot should have 0 annotations"
  end

  test "create_annotation via MCP and verify in sidebar" do
    token, project_id = create_api_key_with_project("Demo Project", "MCP Annotate #{Time.now.to_i}")
    title = "MCP Annot Screenshot #{Time.now.to_i}"
    comment = "Fix this button alignment #{Time.now.to_i}"

    screenshot_result = mcp_create_screenshot(token, project_id, title)
    screenshot_id = screenshot_result["screenshot_id"]

    response = call_mcp_tool(
      token: token,
      tool_name: "create_annotation",
      arguments: {
        project_id: project_id,
        screenshot_id: screenshot_id,
        x_percent: 25.0,
        y_percent: 50.0,
        comment: comment
      }
    )
    assert_equal "200", response.code, "create_annotation should return 200"

    result = parse_mcp_result(response)
    annotation = result["annotation"]
    assert annotation["id"].present?, "Response should include annotation id"
    assert_equal comment, annotation["comment"], "Annotation comment should match"

    visit_app_url screenshot_result["annotate_url"]
    assert_on_screenshot_show
    assert_annotation_visible(comment)
  end

  test "list_annotations returns annotations for screenshot" do
    token, project_id = create_api_key_with_project("Demo Project", "MCP ListAnn #{Time.now.to_i}")
    title = "MCP ListAnn Screenshot #{Time.now.to_i}"
    comment = "Check spacing #{Time.now.to_i}"

    screenshot_result = mcp_create_screenshot(token, project_id, title)
    screenshot_id = screenshot_result["screenshot_id"]

    call_mcp_tool(
      token: token,
      tool_name: "create_annotation",
      arguments: { project_id: project_id, screenshot_id: screenshot_id, x_percent: 10.0, y_percent: 20.0, comment: comment }
    )

    response = call_mcp_tool(
      token: token,
      tool_name: "list_annotations",
      arguments: { project_id: project_id, screenshot_id: screenshot_id }
    )
    assert_equal "200", response.code, "list_annotations should return 200"

    result = parse_mcp_result(response)
    annotations = result["annotations"]

    assert annotations.is_a?(Array), "Response should contain annotations array"
    assert_equal 1, annotations.size, "Should have exactly 1 annotation"
    assert_equal comment, annotations.first["comment"], "Annotation comment should match"
    assert_equal screenshot_id, annotations.first["screenshot_id"], "Annotation should belong to the correct screenshot"
  end

  test "resolve_annotation marks annotation resolved" do
    token, project_id = create_api_key_with_project("Demo Project", "MCP Resolve #{Time.now.to_i}")
    title = "MCP Resolve Screenshot #{Time.now.to_i}"

    screenshot_result = mcp_create_screenshot(token, project_id, title)
    screenshot_id = screenshot_result["screenshot_id"]

    ann_response = call_mcp_tool(
      token: token,
      tool_name: "create_annotation",
      arguments: { project_id: project_id, screenshot_id: screenshot_id, x_percent: 50.0, y_percent: 50.0, comment: "Resolve me" }
    )
    annotation_id = parse_mcp_result(ann_response).dig("annotation", "id")

    response = call_mcp_tool(
      token: token,
      tool_name: "resolve_annotation",
      arguments: { project_id: project_id, annotation_id: annotation_id }
    )
    assert_equal "200", response.code, "resolve_annotation should return 200"

    result = parse_mcp_result(response)
    assert_equal true, result["success"], "resolve_annotation should return success: true"
    assert_equal "resolved", result.dig("annotation", "status"), "Annotation status should be resolved"

    # Confirm via list_annotations
    list_response = call_mcp_tool(
      token: token,
      tool_name: "list_annotations",
      arguments: { project_id: project_id, screenshot_id: screenshot_id, status: "resolved" }
    )
    list_result = parse_mcp_result(list_response)
    assert_equal 1, list_result["annotations"].size, "Should find 1 resolved annotation"
  end

  test "get_annotation returns annotation with coordinates" do
    token, project_id = create_api_key_with_project("Demo Project", "MCP GetAnn #{Time.now.to_i}")
    title = "MCP GetAnn Screenshot #{Time.now.to_i}"
    comment = "Check this region #{Time.now.to_i}"

    screenshot_result = mcp_create_screenshot(token, project_id, title)
    screenshot_id = screenshot_result["screenshot_id"]

    ann_response = call_mcp_tool(
      token: token,
      tool_name: "create_annotation",
      arguments: {
        project_id: project_id,
        screenshot_id: screenshot_id,
        x_percent: 30.0,
        y_percent: 40.0,
        width_percent: 20.0,
        height_percent: 15.0,
        comment: comment
      }
    )
    annotation_id = parse_mcp_result(ann_response).dig("annotation", "id")

    response = call_mcp_tool(
      token: token,
      tool_name: "get_annotation",
      arguments: { project_id: project_id, annotation_id: annotation_id }
    )
    assert_equal "200", response.code, "get_annotation should return 200"

    result = parse_mcp_result(response)
    assert_equal annotation_id, result["id"], "Annotation ID should match"
    assert_equal comment, result["comment"], "Comment should match"
    assert_equal "open", result["status"], "Status should be open"
    assert_equal screenshot_id, result["screenshot_id"], "Screenshot ID should match"
    assert result["screenshot_status"].present?, "Response should include screenshot_status"

    coords = result["coordinates"]
    assert_in_delta 30.0, coords["x_percent"], 0.1, "x_percent should match"
    assert_in_delta 40.0, coords["y_percent"], 0.1, "y_percent should match"
    assert_in_delta 20.0, coords["width_percent"], 0.1, "width_percent should match"
    assert_in_delta 15.0, coords["height_percent"], 0.1, "height_percent should match"
  end

  test "MCP rejects request without auth" do
    response = call_mcp_tool(token: nil, tool_name: "list_screenshots", arguments: { project_id: 1 })
    assert_equal "401", response.code, "MCP should reject unauthenticated requests with 401"
  end

  test "MCP rejects revoked API key" do
    key_name = "MCP Revoke #{Time.now.to_i}"
    token, project_id = create_api_key_with_project("Demo Project", key_name)

    # Verify it works before revoking
    response = call_mcp_tool(token: token, tool_name: "list_screenshots", arguments: { project_id: project_id })
    assert_equal "200", response.code, "Token should work before revoking"

    # Revoke via UI
    visit_api_keys("Demo Project")
    revoke_api_key(key_name)

    # Verify the revoked token is rejected
    response = call_mcp_tool(token: token, tool_name: "list_screenshots", arguments: { project_id: project_id })
    assert_equal "401", response.code, "Revoked token should be rejected with 401"
  end

  private

  def create_api_key_with_project(project_name, key_name)
    token = create_api_key(project_name, key_name)
    project_id = current_url.match(%r{/projects/(\d+)})[1].to_i
    [ token, project_id ]
  end

  def call_mcp_tool(token:, tool_name:, arguments: {})
    uri = URI("#{app_base_url}/mcp")
    request = Net::HTTP::Post.new(uri)
    request["Authorization"] = "Bearer #{token}" if token
    request["Content-Type"] = "application/json"
    request.body = {
      jsonrpc: "2.0",
      id: SecureRandom.uuid,
      method: "tools/call",
      params: { name: tool_name, arguments: arguments }
    }.to_json

    Net::HTTP.start(uri.hostname, uri.port) { |http| http.request(request) }
  end

  def parse_mcp_result(response)
    body = JSON.parse(response.body)
    JSON.parse(body.dig("result", "content", 0, "text"))
  end

  def mcp_create_screenshot(token, project_id, title)
    image_base64 = Base64.strict_encode64(File.binread(TEST_IMAGE_PATH))
    response = call_mcp_tool(
      token: token,
      tool_name: "create_screenshot",
      arguments: { project_id: project_id, title: title, image_base64: image_base64 }
    )
    assert_equal "200", response.code, "MCP create_screenshot should return 200"
    parse_mcp_result(response)
  end
end
