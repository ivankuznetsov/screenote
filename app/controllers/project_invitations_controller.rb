# frozen_string_literal: true

class ProjectInvitationsController < ApplicationController
  include ProjectAuthorization

  before_action :set_project
  before_action :require_owner!

  def create
    @invitation = @project.project_invitations.build(invitation_params)
    @invitation.inviter = Current.user

    if @invitation.save
      ProjectInvitationMailer.invite(@invitation).deliver_later
      redirect_to project_memberships_path(@project), notice: "Invitation sent to #{@invitation.email}."
    else
      redirect_to project_memberships_path(@project), alert: @invitation.errors.full_messages.to_sentence
    end
  end

  def destroy
    @invitation = @project.project_invitations.pending.find(params[:id])
    @invitation.destroy
    redirect_to project_memberships_path(@project), notice: "Invitation cancelled."
  end

  private

  def invitation_params
    params.require(:project_invitation).permit(:email)
  end
end
