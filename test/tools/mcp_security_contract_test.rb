# frozen_string_literal: true

# screenote-edition: self_hosted

require "test_helper"

class McpSecurityContractTest < ActiveSupport::TestCase
  EXPECTED_TOOL_POLICIES = {
    "add_annotation_comment" => [ "mcp_write", false, false, false, false ],
    "cancel_invitation" => [ "mcp_write", false, true, false, false ],
    "create_annotation" => [ "mcp_write", false, false, false, false ],
    "create_multi_viewport_screenshot" => [ "mcp_write", false, false, false, false ],
    "create_project" => [ "mcp_write", false, false, false, false ],
    "create_screenshot" => [ "mcp_write", false, false, false, false ],
    "create_screenshot_upload" => [ "mcp_write", false, false, false, false ],
    "create_snapshot" => [ "mcp_write", false, false, false, false ],
    "get_annotation" => [ "mcp_read", true, false, true, false ],
    "invite_collaborator" => [ "mcp_write", false, false, false, true ],
    "list_annotations" => [ "mcp_read", true, false, true, false ],
    "list_pages" => [ "mcp_read", true, false, true, false ],
    "list_project_members" => [ "mcp_read", true, false, true, false ],
    "list_projects" => [ "mcp_read", true, false, true, false ],
    "list_screenshots" => [ "mcp_read", true, false, true, false ],
    "remove_project_member" => [ "mcp_write", false, true, false, false ],
    "reopen_annotation" => [ "mcp_write", false, false, false, false ],
    "resolve_annotation" => [ "mcp_write", false, false, false, false ]
  }.freeze

  setup do
    @user = users(:alice)
    @project = projects(:alice_project)
    @api_key = api_keys(:alice_key)
  end

  teardown do
    Current.reset
  end

  test "registry contains only explicitly approved tools with complete safety metadata" do
    policies = Screenote::McpToolRegistry.tool_classes.to_h do |tool_class|
      policy = tool_class.mcp_policy
      annotations = policy.fetch(:annotations)
      [
        tool_class.tool_name,
        [
          policy.fetch(:scope),
          annotations.fetch(:read_only_hint),
          annotations.fetch(:destructive_hint),
          annotations.fetch(:idempotent_hint),
          annotations.fetch(:open_world_hint)
        ]
      ]
    end

    assert_equal EXPECTED_TOOL_POLICIES, policies
    assert_empty policies.keys.grep(/bootstrap|admin|account|recovery|transfer|secret|publication/)
  end

  test "read and write OAuth scopes are orthogonal at the tool boundary" do
    Current.authenticated_principal = principal(scopes: [ "mcp_read" ])
    assert ListProjectsTool.new.authorized?
    assert_not CreateProjectTool.new.authorized?(name: "Not writable")

    Current.authenticated_principal = principal(scopes: [ "mcp_write" ])
    assert_not ListProjectsTool.new.authorized?
    assert CreateProjectTool.new.authorized?(name: "Writable")
  end

  test "project API keys can use bound project tools but not person-only actions" do
    Current.authenticated_principal = api_key_principal

    assert ListScreenshotsTool.new.authorized?(project_id: @project.id)
    assert CreateAnnotationTool.new.authorized?(
      project_id: @project.id,
      screenshot_id: screenshots(:alice_screenshot).id,
      x_percent: 10.0,
      y_percent: 20.0,
      comment: "API key actor"
    )
    assert_not CreateProjectTool.new.authorized?(name: "Escaped project")
    assert_not InviteCollaboratorTool.new.authorized?(
      project_id: @project.id,
      email: "invitee@example.com"
    )
  end

  test "API key annotation actions remain attributed to the key rather than its issuer" do
    Current.authenticated_principal = api_key_principal

    created = JSON.parse(CreateAnnotationTool.new.call(
      project_id: @project.id,
      screenshot_id: screenshots(:alice_screenshot).id,
      x_percent: 25.0,
      y_percent: 30.0,
      comment: "Key-authored annotation"
    ))
    annotation = Annotation.find(created.dig("annotation", "id"))
    assert_equal @api_key, annotation.api_key
    assert_nil annotation.user

    AddAnnotationCommentTool.new.call(
      project_id: @project.id,
      annotation_id: annotation.id,
      body: "Key-authored reply"
    )
    reply = annotation.annotation_comments.order(:id).last
    assert_equal @api_key, reply.api_key
    assert_nil reply.user

    ResolveAnnotationTool.new.call(project_id: @project.id, annotation_id: annotation.id)
    annotation.reload
    assert_equal @api_key, annotation.resolved_by_api_key
    assert_nil annotation.resolved_by_user
    assert_equal @api_key, annotation.annotation_comments.order(:id).last.api_key

    ReopenAnnotationTool.new.call(
      project_id: @project.id,
      annotation_id: annotation.id,
      reason: "Still needs work"
    )
    assert_equal @api_key, annotation.annotation_comments.order(:id).last.api_key
  end

  test "transport clears request identity before dispatch and after failures" do
    stale_principal = principal(scopes: [ "mcp_read" ])
    seen_principal = :not_called
    app = lambda do |_environment|
      seen_principal = Current.authenticated_principal
      Current.authenticated_principal = stale_principal
      raise "downstream failure"
    end
    transport = ProjectAuthTransport.new(
      app,
      FastMcp::Server.new(name: "request-reset-test", version: "1"),
      path_prefix: "/mcp",
      auth_token: "unused",
      logger: Rails.logger
    )
    Current.authenticated_principal = stale_principal

    assert_raises(RuntimeError) do
      transport.call(Rack::MockRequest.env_for("/outside-mcp"))
    end

    assert_nil seen_principal
    assert_nil Current.authenticated_principal
  end

  private

  def principal(scopes:)
    AuthenticatedPrincipal.new(
      kind: :user,
      user: @user,
      issuer: @user,
      scopes: scopes
    )
  end

  def api_key_principal
    AuthenticatedPrincipal.new(
      kind: :project,
      user: nil,
      issuer: @user,
      project: @project,
      api_key: @api_key,
      scopes: AuthenticatedPrincipal::API_KEY_SCOPES
    )
  end
end
