# frozen_string_literal: true

class InviteCollaboratorTool < ApplicationTool
  tool_name "invite_collaborator"
  description "Create a private project invitation for an email address. Requires owner role."
  mcp_action scope: :mcp_write, read_only: false, destructive: false, idempotent: false, open_world: true
  authorize { current_user.present? }

  arguments do
    required(:project_id).filled(:integer).description("The project ID")
    required(:email).filled(:string).description("Email address of the person to invite")
  end

  def call(project_id:, email:)
    error = require_project(project_id)
    return error if error

    with_error_handling do
      result = ProjectInvitations::Issue.call(
        principal: current_principal,
        project: current_project,
        email: email
      )

      serialize_result(result)
    end
  end

  private

  def serialize_result(result)
    if result.success?
      return {
        invitation: {
          id: result.invitation.id,
          email: result.invitation.email,
          status: result.invitation.status,
          created_at: result.invitation.created_at.iso8601
        },
        issuance_status: result.status,
        private_link: result.presentation.url,
        manual_code: result.presentation.manual_code,
        warning: "Private invitation credential. Share only with the intended recipient."
      }.to_json
    end

    case result.status
    when :forbidden, :inactive_issuer
      { error: "forbidden", message: "Only active project owners can invite collaborators" }.to_json
    when :already_member
      { error: "already_member", message: "That person is already a project member" }.to_json
    when :limit_reached
      { error: "member_limit_exceeded", message: "Project has reached its member limit" }.to_json
    when :invalid
      { error: "validation_failed", message: result.errors.presence&.to_sentence || "Enter a valid email address" }.to_json
    when :not_found
      { error: "not_found", message: "Project not found" }.to_json
    when :retryable_busy
      { error: "retryable_busy", message: "Invitation issuance is busy; retry the request" }.to_json
    end
  end
end
