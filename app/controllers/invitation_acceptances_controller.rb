# frozen_string_literal: true

class InvitationAcceptancesController < ApplicationController
  skip_before_action :require_authentication

  before_action :set_invitation

  def show
  end

  def create
    user = find_or_create_user(@invitation.email)

    destroy_current_session if Current.user && Current.user.email != @invitation.email
    create_session_for(user) unless Current.user == user

    @invitation.accept!(user)
    redirect_to project_path(@invitation.project), notice: "You've joined \"#{@invitation.project.name}\"!"
  end

  private

  def set_invitation
    @invitation = ProjectInvitation.find_by_token_for(:accept, params[:token])

    unless @invitation
      redirect_to root_path, alert: "This invitation link is invalid or has expired."
    end
  end

  def find_or_create_user(email)
    User.find_by(email: email) || User.create!(
      email: email,
      password: SecureRandom.base64(32),
      confirmed_at: Time.current
    )
  end
end
