# frozen_string_literal: true

class RemoveProjectMemberTool < ApplicationTool
  tool_name "remove_project_member"
  description "Remove a member from a project. Cannot remove yourself or the sole owner. Requires owner role."

  arguments do
    required(:project_id).filled(:integer).description("The project ID")
    required(:membership_id).filled(:integer).description("The membership ID to remove")
  end

  def call(project_id:, membership_id:)
    error = require_project(project_id)
    return error if error

    with_error_handling do
      unless current_project.owner?(current_user)
        return { error: "forbidden", message: "Only project owners can remove members" }.to_json
      end

      membership = current_project.project_memberships.find(membership_id)

      if membership.user == current_user
        return { error: "cannot_remove_self", message: "You cannot remove yourself from the project" }.to_json
      end

      unless membership.destroy
        return { error: "validation_failed", message: membership.errors.full_messages.to_sentence }.to_json
      end

      { success: true, message: "#{membership.user.email} removed from project" }.to_json
    end
  end
end
