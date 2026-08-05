# frozen_string_literal: true

class ApplicationTool < FastMcp::Tool
  MCP_SCOPES = %w[mcp_read mcp_write].freeze

  class << self
    attr_reader :mcp_policy

    def mcp_action(scope:, read_only:, destructive:, idempotent:, open_world:)
      scope = scope.to_s
      raise ArgumentError, "unsupported MCP scope: #{scope}" unless MCP_SCOPES.include?(scope)

      safety_annotations = {
        read_only_hint: read_only,
        destructive_hint: destructive,
        idempotent_hint: idempotent,
        open_world_hint: open_world
      }.freeze
      @mcp_policy = { scope: scope, annotations: safety_annotations }.freeze
      annotations(safety_annotations)
      authorize { current_principal&.allows_scope?(self.class.mcp_policy.fetch(:scope)) }
    end
  end

  private

  def current_principal
    Current.authenticated_principal
  end

  def current_project
    @current_project || current_principal&.project
  end

  def current_user
    current_principal&.user
  end

  def resolve_project(project_id)
    @current_project = current_principal&.resolve_project(project_id)
  end

  def require_project(project_id)
    project = resolve_project(project_id)
    unless project
      if project_id.present?
        return { error: "forbidden", message: "You don't have access to that project" }.to_json
      else
        return { error: "missing_project_id", message: "project_id is required" }.to_json
      end
    end
    nil
  end

  def current_actor_attributes
    current_principal.annotation_actor_attributes
  end

  def with_error_handling
    yield
  rescue Projects::Create::Forbidden => e
    { error: "forbidden", message: e.message }.to_json
  rescue Projects::Create::LimitReached => e
    { error: "project_limit_reached", message: e.message }.to_json
  rescue ActiveRecord::RecordNotFound => e
    { error: "not_found", message: e.message }.to_json
  rescue ActiveRecord::RecordInvalid => e
    { error: "validation_failed", message: e.message, details: e.record.errors.full_messages }.to_json
  rescue StandardError => e
    Screenote::Monitoring.notify(e)
    { error: "internal_error", message: "An unexpected error occurred" }.to_json
  end

  # Shared structured response for argument-validation failures so every MCP
  # tool returns the same envelope to the agent.
  def invalid(message)
    { error: "invalid_arguments", message: message }.to_json
  end

  def project_annotations(project)
    Api::V1::ProjectScope.annotations(project)
  end

  def serialize_annotation(annotation)
    Api::V1::ContractSerializer.annotation(annotation)
  end
end
