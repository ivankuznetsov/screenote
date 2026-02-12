# frozen_string_literal: true

require "test_helper"

class McpToolsTest < ActiveSupport::TestCase
  setup do
    @project = projects(:alice_project)
    @api_key = api_keys(:alice_key)
    @screenshot = screenshots(:alice_screenshot)
    @annotation = annotations(:point_annotation)

    Current.mcp_project = @project
    Current.mcp_api_key = @api_key
  end

  teardown do
    Current.reset
  end

  # CreateScreenshotTool
  test "create_screenshot creates screenshot with image" do
    tool = CreateScreenshotTool.new
    image_data = Base64.strict_encode64(File.binread(Rails.root.join("test/fixtures/files/test_image.png")))

    result = JSON.parse(tool.call(title: "MCP Upload", image_base64: image_data))

    assert result["screenshot_id"].present?, "Should return screenshot ID"
    assert result["annotate_url"].present?, "Should return annotate URL"

    screenshot = Screenshot.find(result["screenshot_id"])
    assert_equal "MCP Upload", screenshot.title
    assert_equal @project.id, screenshot.project_id
    assert screenshot.image.attached?, "Image should be attached"
  end

  # ListScreenshotsTool
  test "list_screenshots returns project screenshots" do
    result = JSON.parse(ListScreenshotsTool.new.call)

    ids = result.map { |s| s["id"] }
    assert_includes ids, @screenshot.id
    assert_not_includes ids, screenshots(:bob_screenshot).id, "Should not include other project's screenshots"
  end

  test "list_screenshots filters by status" do
    result = JSON.parse(ListScreenshotsTool.new.call(status: "ready"))

    statuses = result.map { |s| s["status"] }
    assert statuses.all? { |s| s == "ready" }, "All screenshots should be ready"
  end

  test "list_screenshots includes annotation counts" do
    result = JSON.parse(ListScreenshotsTool.new.call)
    screenshot_data = result.find { |s| s["id"] == @screenshot.id }

    assert screenshot_data["annotation_count"].is_a?(Integer)
    assert screenshot_data["unresolved_count"].is_a?(Integer)
  end

  # ListAnnotationsTool
  test "list_annotations returns project annotations" do
    result = JSON.parse(ListAnnotationsTool.new.call)

    ids = result.map { |a| a["id"] }
    assert_includes ids, annotations(:point_annotation).id
    assert_includes ids, annotations(:region_annotation).id
    assert_not_includes ids, annotations(:bob_annotation).id, "Should not include other project's annotations"
  end

  test "list_annotations filters by screenshot" do
    result = JSON.parse(ListAnnotationsTool.new.call(screenshot_id: @screenshot.id))

    screenshot_ids = result.map { |a| a["screenshot_id"] }.uniq
    assert_equal [ @screenshot.id ], screenshot_ids
  end

  test "list_annotations filters by status" do
    result = JSON.parse(ListAnnotationsTool.new.call(status: "open"))

    statuses = result.map { |a| a["status"] }
    assert statuses.all? { |s| s == "open" }, "All annotations should be open"
  end

  # GetAnnotationTool
  test "get_annotation returns annotation details" do
    result = JSON.parse(GetAnnotationTool.new.call(annotation_id: @annotation.id))

    assert_equal @annotation.id, result["id"]
    assert_equal @annotation.screenshot_id, result["screenshot_id"]
    assert_equal "point", result["type"]
    assert_equal @annotation.comment, result["comment"]
    assert_equal "open", result["status"]
    assert_equal @annotation.user.email, result["author"]
    assert result["coordinates"].is_a?(Hash)
    assert_equal @annotation.x_percent, result["coordinates"]["x_percent"]
  end

  test "get_annotation returns screenshot_status in response" do
    result = JSON.parse(GetAnnotationTool.new.call(annotation_id: @annotation.id))
    assert result.key?("screenshot_status"), "Should include screenshot_status"
  end

  test "get_annotation returns not_found for other projects annotation" do
    result = JSON.parse(GetAnnotationTool.new.call(annotation_id: annotations(:bob_annotation).id))
    assert_equal "not_found", result["error"], "Should return structured not_found error"
  end

  # ResolveAnnotationTool
  test "resolve_annotation marks annotation as resolved" do
    result = JSON.parse(ResolveAnnotationTool.new.call(annotation_id: @annotation.id))

    assert result["success"], "Should return success"
    assert_equal "resolved", result["annotation"]["status"]
    assert_equal "resolved", @annotation.reload.status
    assert_equal @api_key.id, @annotation.resolved_by_api_key_id, "Should record which API key resolved it"
  end

  test "resolve_annotation returns not_found for other projects annotation" do
    result = JSON.parse(ResolveAnnotationTool.new.call(annotation_id: annotations(:bob_annotation).id))
    assert_equal "not_found", result["error"], "Should return structured not_found error"
  end

  # CreateScreenshotTool validations
  test "create_screenshot rejects invalid mime type" do
    tool = CreateScreenshotTool.new
    image_data = Base64.strict_encode64("fake image data")

    result = JSON.parse(tool.call(title: "Test", image_base64: image_data, mime_type: "text/html"))
    assert_equal "invalid_mime_type", result["error"], "Should reject non-image mime types"
  end
end
