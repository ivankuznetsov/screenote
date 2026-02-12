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
    membership = @project.project_memberships.find(params[:id])

    if membership.user == Current.user
      redirect_to project_memberships_path(@project), alert: "You cannot remove yourself."
      return
    end

    membership.destroy
    redirect_to project_memberships_path(@project), notice: "Member removed."
  end
end
