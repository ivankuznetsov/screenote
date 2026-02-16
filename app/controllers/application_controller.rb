# frozen_string_literal: true

class ApplicationController < ActionController::Base
  include RailsSimpleAuth::Controllers::Concerns::Authentication
  include RailsSimpleAuth::Controllers::Concerns::SessionManagement

  allow_browser versions: :modern
  stale_when_importmap_changes

  before_action :require_authentication
  before_action :handle_pending_invitation

  rescue_from ActiveRecord::RecordNotFound, with: :not_found

  private

  def handle_pending_invitation
    return unless Current.user
    token = session.delete(:pending_invitation_token)
    return unless token

    invitation = ProjectInvitation.find_by_token_for(:accept, token)
    return unless invitation

    invitation.accept!(Current.user)
    redirect_to project_path(invitation.project), notice: "You've joined \"#{invitation.project.name}\"!"
  rescue ProjectInvitation::MemberLimitExceeded
    redirect_to root_path, alert: "This project has reached its member limit. Ask the project owner to upgrade their plan."
  end

  def not_found
    respond_to do |format|
      format.html { render html: File.read(Rails.root.join("public/404.html")).html_safe, layout: false, status: :not_found }
      format.json { render json: { error: "Not found" }, status: :not_found }
    end
  end
end
