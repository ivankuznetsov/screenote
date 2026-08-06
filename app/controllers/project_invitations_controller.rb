# frozen_string_literal: true

class ProjectInvitationsController < ApplicationController
  include ProjectAuthorization

  before_action :set_project
  before_action :require_owner!

  def create
    result = ProjectInvitations::Issue.call(
      principal: AuthenticatedPrincipal.for_user(Current.user),
      project: @project,
      email: invitation_params[:email]
    )

    case result.status
    when :issued
      message = invitation_issued_message(result)
      redirect_to project_memberships_path(@project), notice: message
    when :reissued
      redirect_to project_memberships_path(@project),
        notice: "Invitation link reissued. Copy the new private link below."
    when :already_pending
      redirect_to project_memberships_path(@project),
        notice: "That invitation is already pending. Its private link is available below."
    when :already_member
      redirect_to project_memberships_path(@project), alert: "That person is already a project member."
    when :limit_reached
      redirect_to subscription_path,
        alert: "You've reached the member limit for the current plan. Upgrade to invite more collaborators."
    when :invalid
      redirect_to project_memberships_path(@project),
        alert: result.errors.presence&.to_sentence || "Enter a valid email address."
    when :inactive_issuer
      redirect_to new_session_path, alert: "Your account is not active."
    when :forbidden
      redirect_to projects_path, alert: "Only active project owners can invite collaborators."
    when :not_found
      raise ActiveRecord::RecordNotFound
    when :retryable_busy
      redirect_to project_memberships_path(@project),
        alert: "The invitation is busy. Please try again."
    else
      redirect_to project_memberships_path(@project), alert: "The invitation could not be created."
    end
  end

  def destroy
    result = ProjectInvitations::Cancel.call(
      principal: AuthenticatedPrincipal.for_user(Current.user),
      project: @project,
      invitation_id: params[:id]
    )

    case result.status
    when :cancelled
      redirect_to project_memberships_path(@project), notice: "Invitation cancelled."
    when :already_cancelled
      redirect_to project_memberships_path(@project), notice: "Invitation was already cancelled."
    when :already_accepted
      redirect_to project_memberships_path(@project), alert: "This invitation has already been accepted."
    when :forbidden
      redirect_to projects_path, alert: "Only active project owners can cancel invitations."
    when :not_found
      raise ActiveRecord::RecordNotFound
    when :retryable_busy
      redirect_to project_memberships_path(@project),
        alert: "The invitation is busy. Please try again."
    else
      redirect_to project_memberships_path(@project), alert: "The invitation could not be cancelled."
    end
  end

  private

  def invitation_issued_message(result)
    case result.delivery_status
    when :queued
      "Invitation sent to #{result.invitation.email}."
    when :failed
      "Invitation created, but email could not be queued. Copy its private link below."
    else
      "Invitation created. Copy its private link below and share it only with the invitee."
    end
  end

  def invitation_params
    params.require(:project_invitation).permit(:email)
  end
end
