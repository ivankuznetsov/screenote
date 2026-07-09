# frozen_string_literal: true

require "test_helper"

class McpToolsTest < ActiveSupport::TestCase
  setup do
    @user = users(:alice)
    @project = projects(:alice_project)
    @api_key = api_keys(:alice_key)
    @screenshot = screenshots(:alice_screenshot)
    @annotation = annotations(:point_annotation)

    Current.mcp_user = @user
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

    result = JSON.parse(tool.call(project_id: @project.id, title: "MCP Upload", image_base64: image_data))

    assert result["screenshot_id"].present?, "Should return screenshot ID"
    assert result["annotate_url"].present?, "Should return annotate URL"

    screenshot = Screenshot.find(result["screenshot_id"])
    assert_equal "MCP Upload", screenshot.title
    assert_equal @project.id, screenshot.project.id, "Screenshot should belong to the project via page"
    assert screenshot.primary_image.image.attached?, "Image should be attached to the desktop ScreenshotImage"
  end

  # ListScreenshotsTool
  test "list_screenshots returns project screenshots with pagination" do
    result = JSON.parse(ListScreenshotsTool.new.call(project_id: @project.id))

    assert result.key?("pagination"), "Should include pagination metadata"
    assert result["pagination"]["total"].is_a?(Integer)

    ids = result["screenshots"].map { |s| s["id"] }
    assert_includes ids, @screenshot.id
    assert_not_includes ids, screenshots(:bob_screenshot).id, "Should not include other project's screenshots"
  end

  test "list_screenshots filters by status" do
    result = JSON.parse(ListScreenshotsTool.new.call(project_id: @project.id, status: "ready"))

    statuses = result["screenshots"].map { |s| s["status"] }
    assert statuses.all? { |s| s == "ready" }, "All screenshots should be ready"
  end

  test "list_screenshots includes annotation counts" do
    result = JSON.parse(ListScreenshotsTool.new.call(project_id: @project.id))
    screenshot_data = result["screenshots"].find { |s| s["id"] == @screenshot.id }

    assert screenshot_data["annotation_count"].is_a?(Integer)
    assert screenshot_data["unresolved_count"].is_a?(Integer)
  end

  test "list_screenshots respects limit and offset" do
    result = JSON.parse(ListScreenshotsTool.new.call(project_id: @project.id, limit: 1, offset: 0))

    assert_equal 1, result["screenshots"].size, "Should return only 1 screenshot"
    assert_equal 1, result["pagination"]["limit"]
    assert_equal 0, result["pagination"]["offset"]
  end

  # ListAnnotationsTool
  test "list_annotations returns project annotations with pagination" do
    result = JSON.parse(ListAnnotationsTool.new.call(project_id: @project.id))

    assert result.key?("pagination"), "Should include pagination metadata"

    ids = result["annotations"].map { |a| a["id"] }
    assert_includes ids, annotations(:point_annotation).id
    assert_includes ids, annotations(:region_annotation).id
    assert_not_includes ids, annotations(:bob_annotation).id, "Should not include other project's annotations"
  end

  test "list_annotations filters by screenshot" do
    result = JSON.parse(ListAnnotationsTool.new.call(project_id: @project.id, screenshot_id: @screenshot.id))

    screenshot_ids = result["annotations"].map { |a| a["screenshot_id"] }.uniq
    assert_equal [ @screenshot.id ], screenshot_ids
  end

  test "list_annotations filters by status" do
    result = JSON.parse(ListAnnotationsTool.new.call(project_id: @project.id, status: "open"))

    statuses = result["annotations"].map { |a| a["status"] }
    assert statuses.all? { |s| s == "open" }, "All annotations should be open"
  end

  test "list_annotations respects limit and offset" do
    result = JSON.parse(ListAnnotationsTool.new.call(project_id: @project.id, limit: 1, offset: 0))

    assert_equal 1, result["annotations"].size, "Should return only 1 annotation"
    assert_equal 1, result["pagination"]["limit"]
    assert_equal 0, result["pagination"]["offset"]
  end

  test "list_annotations includes viewport on each annotation" do
    result = JSON.parse(ListAnnotationsTool.new.call(project_id: @project.id))

    assert result["annotations"].all? { |a| a.key?("viewport") },
      "Every annotation should carry its viewport for multi-viewport agents"
    assert result["annotations"].all? { |a| %w[desktop tablet mobile].include?(a["viewport"]) },
      "Viewport should be one of desktop/tablet/mobile"
  end

  test "list_annotations filters by viewport" do
    annotations(:point_annotation).update!(viewport: :mobile)

    result = JSON.parse(ListAnnotationsTool.new.call(project_id: @project.id, viewport: "mobile"))

    assert result["annotations"].any?, "Should return at least the mobile annotation"
    assert result["annotations"].all? { |a| a["viewport"] == "mobile" },
      "Filter should exclude non-mobile annotations"
  end

  # CreateSnapshotTool
  test "create_snapshot creates a snapshot for the current project" do
    result = JSON.parse(CreateSnapshotTool.new.call(
      project_id: @project.id,
      git_commit: "abc1234def567890abc1234def567890abc1234d",
      taken_at: "2026-05-14T12:00:00Z"
    ))

    assert result["snapshot_id"].present?
    assert_equal @project.id, result["project_id"]

    snapshot = Snapshot.find(result["snapshot_id"])
    expected_label = "#{snapshot.taken_at.utc.to_date.iso8601} · abc1234"
    assert_equal expected_label, result["label"], "Label should be computed from the stored UTC taken_at date"
    assert_equal "2026-05-14T12:00:00Z", result["taken_at"]

    assert_equal @project, snapshot.project
    assert_equal "abc1234def567890abc1234def567890abc1234d", snapshot.git_commit
  end

  test "create_snapshot normalizes git_commit to lowercase" do
    result = JSON.parse(CreateSnapshotTool.new.call(
      project_id: @project.id,
      git_commit: "AbC1234"
    ))

    snapshot = Snapshot.find(result["snapshot_id"])
    assert_equal "abc1234", snapshot.git_commit,
      "Mixed-case input should not create a snapshot distinct from its lowercase twin"
  end

  test "create_snapshot trims surrounding git_commit whitespace before validation" do
    result = JSON.parse(CreateSnapshotTool.new.call(
      project_id: @project.id,
      git_commit: "  AbC1234\n"
    ))

    snapshot = Snapshot.find(result["snapshot_id"])
    assert_equal "abc1234", snapshot.git_commit
  end

  test "create_snapshot rejects bare date without time component" do
    result = JSON.parse(CreateSnapshotTool.new.call(
      project_id: @project.id,
      git_commit: "abc1234",
      taken_at: "2026-05-14"
    ))

    assert_equal "invalid_arguments", result["error"]
    assert_match(/ISO 8601/, result["message"])
  end

  test "create_snapshot rejects malformed taken_at" do
    result = JSON.parse(CreateSnapshotTool.new.call(
      project_id: @project.id,
      git_commit: "abc1234",
      taken_at: "not-iso"
    ))

    assert_equal "invalid_arguments", result["error"]
    assert_match(/ISO 8601/, result["message"])
  end

  test "create_snapshot rejects a timestamp without an explicit UTC offset" do
    result = JSON.parse(CreateSnapshotTool.new.call(
      project_id: @project.id,
      git_commit: "abc1234",
      taken_at: "2026-05-14T12:00:00"
    ))

    assert_equal "invalid_arguments", result["error"]
    assert_match(/ISO 8601/, result["message"])
  end

  test "create_snapshot rejects empty git_commit" do
    result = JSON.parse(CreateSnapshotTool.new.call(
      project_id: @project.id,
      git_commit: ""
    ))

    assert_equal "invalid_arguments", result["error"], "Empty git_commit must trip validation, not silently create"
  end

  test "create_snapshot rejects sub-7-char git_commit" do
    result = JSON.parse(CreateSnapshotTool.new.call(
      project_id: @project.id,
      git_commit: "abc12"
    ))

    assert_equal "invalid_arguments", result["error"]
    assert_match(/git_commit/, result["message"])
  end

  test "create_snapshot rejects over-40-char git_commit" do
    result = JSON.parse(CreateSnapshotTool.new.call(
      project_id: @project.id,
      git_commit: "a" * 41
    ))

    assert_equal "invalid_arguments", result["error"]
    assert_match(/git_commit/, result["message"])
  end

  test "create_snapshot rejects inaccessible project" do
    Current.mcp_project = nil

    result = JSON.parse(CreateSnapshotTool.new.call(
      project_id: projects(:bob_project).id,
      git_commit: "abc1234"
    ))

    assert_equal "forbidden", result["error"]
  end

  test "create_snapshot rejects malformed git_commit" do
    result = JSON.parse(CreateSnapshotTool.new.call(
      project_id: @project.id,
      git_commit: "not-a-hash"
    ))

    assert_equal "invalid_arguments", result["error"]
    assert_match(/git_commit/, result["message"])
  end

  test "create_snapshot defaults taken_at to now" do
    travel_to Time.zone.parse("2026-05-14 13:15:00") do
      result = JSON.parse(CreateSnapshotTool.new.call(
        project_id: @project.id,
        git_commit: "abc1234"
      ))

      snapshot = Snapshot.find(result["snapshot_id"])
      assert_equal Time.current, snapshot.taken_at
    end
  end

  test "create_snapshot parses provided ISO8601 taken_at" do
    result = JSON.parse(CreateSnapshotTool.new.call(
      project_id: @project.id,
      git_commit: "abc1234",
      taken_at: "2026-05-14T08:30:00Z"
    ))

    snapshot = Snapshot.find(result["snapshot_id"])
    assert_equal Time.utc(2026, 5, 14, 8, 30), snapshot.taken_at
  end

  test "create_snapshot rejects future taken_at" do
    travel_to Time.zone.parse("2026-05-14 12:00:00") do
      result = JSON.parse(CreateSnapshotTool.new.call(
        project_id: @project.id,
        git_commit: "abc1234",
        taken_at: "2026-05-14T12:10:01Z"
      ))

      assert_equal "validation_failed", result["error"]
      assert_match(/future/, result["message"])
    end
  end

  test "create_snapshot accepts non-UTC offsets and keeps label/taken_at consistent" do
    # Round-trips through `Time.iso8601(...).in_time_zone`, so a 23:00 wall time
    # at -05:00 lands as 04:00 UTC on the next day. The label uses that stable
    # UTC date so collaborators in different request zones see the same row.
    travel_to Time.zone.parse("2026-05-15 05:00:00") do
      result = JSON.parse(CreateSnapshotTool.new.call(
        project_id: @project.id,
        git_commit: "abc1234",
        taken_at: "2026-05-14T23:00:00-05:00"
      ))

      snapshot = Snapshot.find(result["snapshot_id"])
      assert_equal Time.utc(2026, 5, 15, 4, 0), snapshot.taken_at,
        "taken_at must be normalized to UTC equivalent of the offset input"
      assert_equal "2026-05-15 · abc1234", result["label"],
        "label day should match the stored UTC taken_at, not the input wall time"
    end
  end

  # CreateMultiViewportScreenshotTool
  test "create_multi_viewport_screenshot returns one upload URL per requested viewport" do
    result = JSON.parse(CreateMultiViewportScreenshotTool.new.call(
      project_id: @project.id, title: "Multi capture",
      viewports: [
        { viewport: "desktop", mime_type: "image/png" },
        { viewport: "tablet",  mime_type: "image/png" },
        { viewport: "mobile",  mime_type: "image/png" }
      ]
    ))

    assert result["screenshot_id"].present?
    assert result["annotate_url"].present?
    assert_equal 3, result["uploads"].size
    assert_equal %w[desktop tablet mobile], result["uploads"].map { |u| u["viewport"] }
    assert result["uploads"].all? { |u| u["upload_url"].present? && u["token"].present? }

    screenshot = Screenshot.find(result["screenshot_id"])
    assert_equal 3, screenshot.screenshot_images.count
  end

  test "create_multi_viewport_screenshot links screenshot to snapshot" do
    snapshot = snapshots(:latest)

    result = JSON.parse(CreateMultiViewportScreenshotTool.new.call(
      project_id: @project.id,
      title: "Snapshot capture",
      snapshot_id: snapshot.id,
      viewports: [ { viewport: "desktop", mime_type: "image/png" } ]
    ))

    screenshot = Screenshot.find(result["screenshot_id"])
    assert_equal snapshot, screenshot.snapshot
    assert_equal snapshot.id, result["snapshot_id"]
  end

  test "create_multi_viewport_screenshot without snapshot_id creates ad-hoc screenshot" do
    result = JSON.parse(CreateMultiViewportScreenshotTool.new.call(
      project_id: @project.id,
      title: "Ad-hoc capture",
      viewports: [ { viewport: "desktop", mime_type: "image/png" } ]
    ))

    screenshot = Screenshot.find(result["screenshot_id"])
    assert_nil screenshot.snapshot_id
    assert_nil result["snapshot_id"]
  end

  test "create_multi_viewport_screenshot rejects snapshot from another project" do
    other_snapshot = projects(:bob_project).snapshots.create!(
      git_commit: "abc1234",
      taken_at: Time.current
    )

    assert_no_difference "Screenshot.count" do
      result = JSON.parse(CreateMultiViewportScreenshotTool.new.call(
        project_id: @project.id,
        title: "Wrong snapshot",
        snapshot_id: other_snapshot.id,
        viewports: [ { viewport: "desktop", mime_type: "image/png" } ]
      ))

      assert_equal "invalid_arguments", result["error"]
      assert_match(/snapshot not found/, result["message"])
    end
  end

  test "create_multi_viewport_screenshot with only one entry creates a single variant" do
    result = JSON.parse(CreateMultiViewportScreenshotTool.new.call(
      project_id: @project.id, title: "Just mobile",
      viewports: [ { viewport: "mobile", mime_type: "image/png" } ]
    ))

    assert_equal 1, result["uploads"].size
    assert_equal "mobile", result["uploads"].first["viewport"]
  end

  test "create_multi_viewport_screenshot rejects duplicate viewports" do
    result = JSON.parse(CreateMultiViewportScreenshotTool.new.call(
      project_id: @project.id, title: "Dup",
      viewports: [
        { viewport: "desktop", mime_type: "image/png" },
        { viewport: "desktop", mime_type: "image/png" }
      ]
    ))

    assert_equal "invalid_arguments", result["error"]
    assert_match(/unique/, result["message"])
  end

  test "create_multi_viewport_screenshot rejects unknown viewport names" do
    result = JSON.parse(CreateMultiViewportScreenshotTool.new.call(
      project_id: @project.id, title: "Bad",
      viewports: [ { viewport: "wide", mime_type: "image/png" } ]
    ))

    assert_equal "invalid_arguments", result["error"]
    assert_match(/desktop, tablet, mobile/, result["message"])
  end

  test "create_annotation rejects viewport that doesn't exist on the screenshot" do
    # @screenshot has only desktop — no tablet / mobile variants
    assert_equal %w[desktop], @screenshot.available_viewports

    result = JSON.parse(CreateAnnotationTool.new.call(
      project_id: @project.id, screenshot_id: @screenshot.id,
      x_percent: 10.0, y_percent: 10.0, comment: "Wrong viewport",
      viewport: "mobile"
    ))

    assert_equal "invalid_arguments", result["error"]
    assert_match(/no mobile variant/, result["message"])
  end

  test "create_annotation requires viewport on multi-variant screenshots" do
    @screenshot.screenshot_images.create!(viewport: :mobile)
    assert_equal 2, @screenshot.screenshot_images.count

    result = JSON.parse(CreateAnnotationTool.new.call(
      project_id: @project.id, screenshot_id: @screenshot.id,
      x_percent: 10.0, y_percent: 10.0, comment: "Ambiguous"
      # viewport omitted
    ))

    assert_equal "invalid_arguments", result["error"]
    assert_match(/required for multi-variant/, result["message"])
  end

  test "create_annotation defaults to the sole viewport on single-variant screenshots" do
    assert_equal %w[desktop], @screenshot.available_viewports

    result = JSON.parse(CreateAnnotationTool.new.call(
      project_id: @project.id, screenshot_id: @screenshot.id,
      x_percent: 10.0, y_percent: 10.0, comment: "Implicit desktop"
      # viewport omitted — allowed because only one variant exists
    ))

    assert result["annotation"].present?
    assert_equal "desktop", result["annotation"]["viewport"]
  end

  test "create_multi_viewport_screenshot accepts string-keyed viewport hashes (MCP JSON transport)" do
    # Regression: FastMcp only symbolises top-level keys, not hashes inside
    # arrays. Over the real MCP transport, each entry arrives as
    # { "viewport" => "...", "mime_type" => "..." } — v[:viewport] would be
    # nil and the tool would reject valid input.
    result = JSON.parse(CreateMultiViewportScreenshotTool.new.call(
      project_id: @project.id, title: "String-keyed",
      viewports: [
        { "viewport" => "desktop", "mime_type" => "image/png" },
        { "viewport" => "mobile",  "mime_type" => "image/png" }
      ]
    ))

    assert result["screenshot_id"].present?, "Should accept string-keyed hashes: #{result.inspect}"
    assert_equal 2, result["uploads"].size
  end

  test "create_multi_viewport_screenshot tokens resolve to the matching ScreenshotImage" do
    result = JSON.parse(CreateMultiViewportScreenshotTool.new.call(
      project_id: @project.id, title: "Token check",
      viewports: [
        { viewport: "desktop", mime_type: "image/png" },
        { viewport: "mobile",  mime_type: "image/png" }
      ]
    ))

    screenshot = Screenshot.find(result["screenshot_id"])
    result["uploads"].each do |upload|
      resolved = ScreenshotImage.find_by_token_for(:upload, upload["token"])
      assert_equal screenshot.id, resolved.screenshot_id
      assert_equal upload["viewport"], resolved.viewport
    end
  end

  # GetAnnotationTool
  test "get_annotation returns annotation details" do
    result = JSON.parse(GetAnnotationTool.new.call(project_id: @project.id, annotation_id: @annotation.id))

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
    result = JSON.parse(GetAnnotationTool.new.call(project_id: @project.id, annotation_id: @annotation.id))
    assert result.key?("screenshot_status"), "Should include screenshot_status"
  end

  test "get_annotation returns not_found for other projects annotation" do
    result = JSON.parse(GetAnnotationTool.new.call(project_id: @project.id, annotation_id: annotations(:bob_annotation).id))
    assert_equal "not_found", result["error"], "Should return structured not_found error"
  end

  # ResolveAnnotationTool
  test "resolve_annotation marks annotation as resolved" do
    result = JSON.parse(ResolveAnnotationTool.new.call(project_id: @project.id, annotation_id: @annotation.id))

    assert result["success"], "Should return success"
    assert_equal "resolved", result["annotation"]["status"]
    assert_equal "resolved", @annotation.reload.status
  end

  test "resolve_annotation returns not_found for other projects annotation" do
    result = JSON.parse(ResolveAnnotationTool.new.call(project_id: @project.id, annotation_id: annotations(:bob_annotation).id))
    assert_equal "not_found", result["error"], "Should return structured not_found error"
  end

  # CreateAnnotationTool
  test "create_annotation creates annotation on screenshot" do
    result = JSON.parse(CreateAnnotationTool.new.call(
      project_id: @project.id,
      screenshot_id: @screenshot.id,
      x_percent: 25.0,
      y_percent: 50.0,
      comment: "Agent feedback"
    ))

    annotation_data = result["annotation"]
    assert annotation_data["id"].present?, "Should return annotation ID"
    assert_equal "point", annotation_data["type"]
    assert_equal "Agent feedback", annotation_data["comment"]
    assert_equal "open", annotation_data["status"]

    annotation = Annotation.find(annotation_data["id"])
    assert_equal @screenshot.id, annotation.screenshot_id
    assert_equal 25.0, annotation.x_percent
    assert_equal 50.0, annotation.y_percent
  end

  test "create_annotation creates region annotation" do
    result = JSON.parse(CreateAnnotationTool.new.call(
      project_id: @project.id,
      screenshot_id: @screenshot.id,
      x_percent: 10.0,
      y_percent: 20.0,
      width_percent: 30.0,
      height_percent: 25.0,
      comment: "Region feedback"
    ))

    annotation_data = result["annotation"]
    assert_equal "region", annotation_data["type"]
    assert_equal 30.0, annotation_data["coordinates"]["width_percent"]
    assert_equal 25.0, annotation_data["coordinates"]["height_percent"]
  end

  test "create_annotation returns not_found for other projects screenshot" do
    result = JSON.parse(CreateAnnotationTool.new.call(
      project_id: @project.id,
      screenshot_id: screenshots(:bob_screenshot).id,
      x_percent: 50.0,
      y_percent: 50.0,
      comment: "Should fail"
    ))
    assert_equal "not_found", result["error"], "Should return not_found for other project's screenshot"
  end

  test "create_annotation returns validation_failed for invalid coordinates" do
    result = JSON.parse(CreateAnnotationTool.new.call(
      project_id: @project.id,
      screenshot_id: @screenshot.id,
      x_percent: 150.0,
      y_percent: 50.0,
      comment: "Invalid coords"
    ))
    assert_equal "validation_failed", result["error"], "Should return validation error for out-of-range coordinates"
  end

  # CreateScreenshotUploadTool
  test "create_screenshot_upload creates screenshot and returns upload URL" do
    tool = CreateScreenshotUploadTool.new

    result = JSON.parse(tool.call(project_id: @project.id, title: "Signed Upload"))

    assert result["screenshot_id"].present?, "Should return screenshot ID"
    assert result["upload_url"].present?, "Should return upload URL"
    assert result["annotate_url"].present?, "Should return annotate URL"
    assert_match(/token=/, result["upload_url"], "Upload URL should contain a token")

    screenshot = Screenshot.find(result["screenshot_id"])
    assert_equal "Signed Upload", screenshot.title
    assert_equal @project.id, screenshot.project.id, "Screenshot should belong to the project via page"
    assert_not screenshot.image.attached?, "Image should NOT be attached yet"
  end

  test "create_screenshot_upload rejects invalid mime type" do
    tool = CreateScreenshotUploadTool.new

    result = JSON.parse(tool.call(project_id: @project.id, title: "Bad MIME", mime_type: "text/html"))
    assert_equal "invalid_mime_type", result["error"], "Should reject non-image mime types"
  end

  # CreateScreenshotTool validations
  test "create_screenshot rejects invalid mime type" do
    tool = CreateScreenshotTool.new
    image_data = Base64.strict_encode64("fake image data")

    result = JSON.parse(tool.call(project_id: @project.id, title: "Test", image_base64: image_data, mime_type: "text/html"))
    assert_equal "invalid_mime_type", result["error"], "Should reject non-image mime types"
  end

  # Project access control
  test "tools reject unauthorized project_id" do
    Current.mcp_project = nil # Simulate OAuth auth (no pre-set project)

    bob_project = projects(:bob_project)
    result = JSON.parse(ListScreenshotsTool.new.call(project_id: bob_project.id))

    assert_equal "forbidden", result["error"], "Should reject access to other user's project"
  end

  test "tools require project_id when no pre-set project" do
    Current.mcp_project = nil

    result = JSON.parse(ListScreenshotsTool.new.call(project_id: nil))
    assert_equal "missing_project_id", result["error"], "Should require project_id for OAuth users"
  end

  # ListProjectsTool
  test "list_projects returns user's projects" do
    Current.mcp_project = nil

    result = JSON.parse(ListProjectsTool.new.call)

    project_ids = result["projects"].map { |p| p["id"] }
    assert_includes project_ids, @project.id, "Should include user's project"
    assert_not_includes project_ids, projects(:bob_project).id, "Should not include other user's project"

    project_data = result["projects"].find { |p| p["id"] == @project.id }
    assert project_data["name"].present?, "Should include project name"
    assert project_data["role"].present?, "Should include user's role"
    assert project_data["screenshot_count"].is_a?(Integer)
  end

  # CreateProjectTool
  test "create_project creates a new project" do
    Current.mcp_project = nil

    result = JSON.parse(CreateProjectTool.new.call(name: "Agent Project"))

    project_data = result["project"]
    assert project_data["id"].present?, "Should return project ID"
    assert_equal "Agent Project", project_data["name"]
    assert_equal "owner", project_data["role"]

    project = Project.find(project_data["id"])
    assert_equal @user, project.creator, "User should be the project creator"
    assert project.member?(@user), "User should be a member"
  end

  # ListPagesTool
  test "list_pages returns project pages with version counts" do
    result = JSON.parse(ListPagesTool.new.call(project_id: @project.id))

    assert result["pages"].is_a?(Array), "Should return pages array"
    page_names = result["pages"].map { |p| p["name"] }
    assert_includes page_names, pages(:alice_page).name

    page_data = result["pages"].find { |p| p["name"] == pages(:alice_page).name }
    assert page_data["id"].present?, "Should include page ID"
    assert page_data["version_count"].is_a?(Integer), "Should include version count"
    assert page_data["url"].present?, "Should include page URL"
  end

  # CreateScreenshotTool with page_name
  test "create_screenshot groups under specified page_name" do
    tool = CreateScreenshotTool.new
    image_data = Base64.strict_encode64(File.binread(Rails.root.join("test/fixtures/files/test_image.png")))

    result = JSON.parse(tool.call(
      project_id: @project.id,
      title: "v2",
      page_name: "Login",
      image_base64: image_data
    ))

    assert result["page_id"].present?, "Should return page ID"
    screenshot = Screenshot.find(result["screenshot_id"])
    assert_equal "Login", screenshot.page.name, "Screenshot should be grouped under specified page"
    assert_equal "v2", screenshot.title, "Screenshot title should be the version label"
  end

  # CreateScreenshotUploadTool with page_name
  test "create_screenshot_upload groups under specified page_name" do
    tool = CreateScreenshotUploadTool.new

    result = JSON.parse(tool.call(
      project_id: @project.id,
      title: "v1",
      page_name: "Dashboard"
    ))

    assert result["page_id"].present?, "Should return page ID"
    screenshot = Screenshot.find(result["screenshot_id"])
    assert_equal "Dashboard", screenshot.page.name, "Screenshot should be grouped under specified page"
    assert_equal "v1", screenshot.title
  end

  # ListScreenshotsTool with page_id filter
  test "list_screenshots includes page info" do
    result = JSON.parse(ListScreenshotsTool.new.call(project_id: @project.id))

    screenshot_data = result["screenshots"].find { |s| s["id"] == @screenshot.id }
    assert screenshot_data["page_id"].present?, "Should include page_id"
    assert screenshot_data["page_name"].present?, "Should include page_name"
  end

  test "list_screenshots filters by page_id" do
    page = pages(:alice_page)
    result = JSON.parse(ListScreenshotsTool.new.call(project_id: @project.id, page_id: page.id))

    page_ids = result["screenshots"].map { |s| s["page_id"] }.uniq
    assert_equal [ page.id ], page_ids, "All screenshots should belong to the filtered page"
  end

  # InviteCollaboratorTool
  test "invite_collaborator sends invitation" do
    result = JSON.parse(InviteCollaboratorTool.new.call(project_id: @project.id, email: "new@example.com"))

    assert result["invitation"].present?, "Should return invitation data"
    assert_equal "new@example.com", result["invitation"]["email"]
    assert_equal "pending", result["invitation"]["status"]
  end

  test "invite_collaborator rejects duplicate pending invitation" do
    result = JSON.parse(InviteCollaboratorTool.new.call(project_id: @project.id, email: "newuser@example.com"))

    assert_equal "validation_failed", result["error"], "Should reject duplicate invitation"
  end

  test "invite_collaborator rejects existing member" do
    result = JSON.parse(InviteCollaboratorTool.new.call(project_id: @project.id, email: "bob@example.com"))

    assert_equal "validation_failed", result["error"], "Should reject inviting existing member"
  end

  test "invite_collaborator requires owner role" do
    Current.mcp_user = users(:bob)
    Current.mcp_project = @project

    result = JSON.parse(InviteCollaboratorTool.new.call(project_id: @project.id, email: "someone@example.com"))

    assert_equal "forbidden", result["error"], "Non-owner should not be able to invite"
  end

  # ListProjectMembersTool
  test "list_project_members returns members and pending invitations" do
    result = JSON.parse(ListProjectMembersTool.new.call(project_id: @project.id))

    assert result["members"].is_a?(Array), "Should return members array"
    assert result["pending_invitations"].is_a?(Array), "Should return pending invitations array"

    emails = result["members"].map { |m| m["email"] }
    assert_includes emails, "alice@example.com"
    assert_includes emails, "bob@example.com"

    pending_emails = result["pending_invitations"].map { |i| i["email"] }
    assert_includes pending_emails, "newuser@example.com"
  end

  test "list_project_members includes role info" do
    result = JSON.parse(ListProjectMembersTool.new.call(project_id: @project.id))

    alice_member = result["members"].find { |m| m["email"] == "alice@example.com" }
    assert_equal "owner", alice_member["role"], "Alice should be owner"

    bob_member = result["members"].find { |m| m["email"] == "bob@example.com" }
    assert_equal "member", bob_member["role"], "Bob should be member"
  end

  # CancelInvitationTool
  test "cancel_invitation cancels pending invitation" do
    invitation = project_invitations(:pending_invitation)

    result = JSON.parse(CancelInvitationTool.new.call(project_id: @project.id, invitation_id: invitation.id))

    assert result["success"], "Should return success"
    assert_raises(ActiveRecord::RecordNotFound) { invitation.reload }
  end

  test "cancel_invitation requires owner role" do
    Current.mcp_user = users(:bob)
    Current.mcp_project = @project
    invitation = project_invitations(:pending_invitation)

    result = JSON.parse(CancelInvitationTool.new.call(project_id: @project.id, invitation_id: invitation.id))

    assert_equal "forbidden", result["error"], "Non-owner should not be able to cancel invitations"
  end

  # RemoveProjectMemberTool
  test "remove_project_member removes member" do
    membership = project_memberships(:bob_member_of_alice_project)

    result = JSON.parse(RemoveProjectMemberTool.new.call(project_id: @project.id, membership_id: membership.id))

    assert result["success"], "Should return success"
    assert_raises(ActiveRecord::RecordNotFound) { membership.reload }
  end

  test "remove_project_member cannot remove self" do
    membership = project_memberships(:alice_owns_alice_project)

    result = JSON.parse(RemoveProjectMemberTool.new.call(project_id: @project.id, membership_id: membership.id))

    assert_equal "cannot_remove_self", result["error"], "Should not allow removing yourself"
  end

  test "remove_project_member requires owner role" do
    Current.mcp_user = users(:bob)
    Current.mcp_project = @project
    membership = project_memberships(:alice_owns_alice_project)

    result = JSON.parse(RemoveProjectMemberTool.new.call(project_id: @project.id, membership_id: membership.id))

    assert_equal "forbidden", result["error"], "Non-owner should not be able to remove members"
  end
end
