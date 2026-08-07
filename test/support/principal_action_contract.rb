# frozen_string_literal: true

module PrincipalActionContract
  SURFACES = %i[browser rest public_cli mcp].freeze

  # This is deliberately a capability table, not a claim that every transport
  # has identical commands. REST and the public CLI participate in review
  # threads but do not create annotation geometry.
  ACTIONS = {
    create_project: { browser: true, rest: true, public_cli: true, mcp: true },
    create_point: { browser: true, rest: false, public_cli: false, mcp: true },
    create_area: { browser: true, rest: false, public_cli: false, mcp: true },
    list_annotations: { browser: true, rest: true, public_cli: true, mcp: true },
    get_annotation: { browser: true, rest: true, public_cli: true, mcp: true },
    reply: { browser: true, rest: true, public_cli: true, mcp: true },
    resolve: { browser: true, rest: true, public_cli: true, mcp: true },
    reopen: { browser: true, rest: false, public_cli: false, mcp: true },
    invite_collaborator: { browser: true, rest: false, public_cli: false, mcp: true }
  }.transform_values(&:freeze).freeze

  MCP_TOOLS = {
    create_project: "create_project",
    create_point: "create_annotation",
    create_area: "create_annotation",
    list_annotations: "list_annotations",
    get_annotation: "get_annotation",
    reply: "add_annotation_comment",
    resolve: "resolve_annotation",
    reopen: "reopen_annotation",
    invite_collaborator: "invite_collaborator"
  }.freeze

  REST_ROUTES = {
    create_project: [ "POST", %r{\A/api/v1/projects(?:\(.:format\))?\z} ],
    list_annotations: [ "GET", %r{\A/api/v1/screenshots/:screenshot_id/annotations(?:\(.:format\))?\z} ],
    get_annotation: [ "GET", %r{\A/api/v1/annotations/:id(?:\(.:format\))?\z} ],
    reply: [ "POST", %r{\A/api/v1/annotations/:annotation_id/comments(?:\(.:format\))?\z} ],
    resolve: [ "POST", %r{\A/api/v1/annotations/:annotation_id/resolve(?:\(.:format\))?\z} ]
  }.freeze

  def self.supported?(action, surface)
    ACTIONS.fetch(action).fetch(surface)
  end

  def self.validate!
    unless ACTIONS.values.all? { |support| support.keys == SURFACES }
      raise "principal/action contract must classify every surface"
    end

    declared_mcp_actions = ACTIONS.filter { |_action, support| support.fetch(:mcp) }.keys
    unless declared_mcp_actions.sort == MCP_TOOLS.keys.sort
      raise "every MCP capability must map to one registered tool"
    end

    declared_rest_actions = ACTIONS.filter { |_action, support| support.fetch(:rest) }.keys
    unless declared_rest_actions.sort == REST_ROUTES.keys.sort
      raise "every REST capability must map to one route"
    end

    true
  end
end
