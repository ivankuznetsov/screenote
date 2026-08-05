# frozen_string_literal: true

class ProjectInvitationsController < ApplicationController
  include ProjectAuthorization

  before_action :set_project
  before_action :require_owner!

  def create
    unless Current.user.can_invite_member?(@project)
      redirect_to subscription_path, alert: "You've reached the free plan limit of 1 team member. Upgrade to Pro for unlimited team members."
      return
    end

    @invitation = @project.project_invitations.build(invitation_params)
    @invitation.inviter = Current.user

    if @invitation.save
      if Screenote::Deployment.current.mail?
        ProjectInvitationMailer.invite(@invitation).deliver_later
        notice = "Invitation sent to #{@invitation.email}."
      else
        notice = "Invitation created for #{@invitation.email}. Copy its private link to share it."
      end
      redirect_to project_memberships_path(@project), notice: notice
    else
      redirect_to project_memberships_path(@project), alert: @invitation.errors.full_messages.to_sentence
    end
  end

  def destroy
    @invitation = @project.project_invitations.find(params[:id])

    if @invitation.pending?
      @invitation.destroy
      redirect_to project_memberships_path(@project), notice: "Invitation cancelled."
    else
      redirect_to project_memberships_path(@project), alert: "This invitation has already been accepted."
    end
  end

  private

  def invitation_params
    params.require(:project_invitation).permit(:email)
  end
end
