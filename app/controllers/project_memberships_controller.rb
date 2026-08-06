# frozen_string_literal: true

class ProjectMembershipsController < ApplicationController
  include ProjectAuthorization

  before_action :set_project
  before_action :require_owner!, only: :destroy
  before_action :set_private_headers, only: :index

  def index
    @memberships = @project.project_memberships.includes(:user).order(:created_at)
    @pending_invitations = @project.project_invitations.pending.includes(:authentication_tokens).order(:created_at)
    @is_owner = @project.owner?(Current.user)
    @pending_invitation_presentations = invitation_presentations if @is_owner
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
    when :retryable_busy
      redirect_to project_memberships_path(@project), alert: "Member removal is busy. Please try again."
    else
      redirect_to project_memberships_path(@project), alert: "Member could not be removed."
    end
  end

  private

  def set_private_headers
    response.set_header("Cache-Control", "no-store, max-age=0")
    response.set_header("Pragma", "no-cache")
    response.set_header("Referrer-Policy", "no-referrer")
    response.set_header("X-Robots-Tag", "noindex, nofollow")
  end

  def invitation_presentations
    issuer = AuthenticationLinks::Issuer.new(
      origin: AuthenticationLinks::Runtime.origin,
      keyring: AuthenticationLinks::Runtime.keyring
    )

    @pending_invitations.to_h do |invitation|
      token = invitation.authentication_tokens
        .select(&:invitation?)
        .select(&:outstanding?)
        .max_by(&:generation)
      presentation = issuer.re_present(token: token) if token
      [ invitation.id, presentation ]
    rescue AuthenticationLinks::Issuer::InvalidToken, AuthenticationLinks::Keyring::MissingKey
      [ invitation.id, nil ]
    end
  end
end
