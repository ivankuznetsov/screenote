# frozen_string_literal: true

class ProjectMembershipsController < ApplicationController
  include ProjectAuthorization

  before_action :set_project
  before_action :require_owner!, only: :destroy

  def index
    @memberships = @project.project_memberships.includes(:user).order(:created_at)
    @pending_invitations = @project.project_invitations.pending.order(:created_at)
    @is_owner = @project.owner?(Current.user)
  end

  def destroy
    result = ProjectMemberships::Remove.call(
      project: @project,
      membership_id: params[:id],
      actor: Current.user
    )

    case result.status
    when :removed
      redirect_to project_memberships_path(@project), notice: "Member removed."
    when :cannot_remove_self
      redirect_to project_memberships_path(@project), alert: "You cannot remove yourself."
    when :forbidden
      redirect_to projects_path, alert: "Only project owners can remove members."
    when :not_found
      raise ActiveRecord::RecordNotFound
    when :invalid
      redirect_to project_memberships_path(@project), alert: result.membership.errors.full_messages.to_sentence
    end
  end
end
