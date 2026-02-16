# frozen_string_literal: true

class InvitationAcceptancesController < ApplicationController
  skip_before_action :require_authentication

  before_action :set_invitation

  def show
  end

  def create
    existing_user = User.find_by(email: @invitation.email)

    if existing_user
      unless Current.user == existing_user
        session[:pending_invitation_token] = params[:token]
        redirect_to new_session_path, alert: "Please sign in to accept this invitation."
        return
      end

      @invitation.accept!(existing_user)
      redirect_to project_path(@invitation.project), notice: "You've joined \"#{@invitation.project.name}\"!"
    else
      user = User.find_or_create_by!(email: @invitation.email) do |u|
        u.password = SecureRandom.base64(32)
        u.confirmed_at = Time.current
      end

      create_session_for(user)
      @invitation.accept!(user)
      redirect_to project_path(@invitation.project), notice: "You've joined \"#{@invitation.project.name}\"!"
    end
  rescue ProjectInvitation::MemberLimitExceeded
    redirect_to root_path, alert: "This project has reached its member limit. Ask the project owner to upgrade their plan."
  rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotUnique => e
    Honeybadger.notify(e, context: { invitation_id: @invitation.id, email: @invitation.email })
    redirect_to root_path, alert: "Something went wrong accepting this invitation. Please try again or contact support."
  end

  private

  def set_invitation
    @invitation = ProjectInvitation.find_by_token_for(:accept, params[:token])
    redirect_to root_path, alert: "This invitation link is invalid or has expired." unless @invitation
  end
end
