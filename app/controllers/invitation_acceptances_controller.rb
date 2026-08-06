# frozen_string_literal: true

class InvitationAcceptancesController < ApplicationController
  skip_before_action :require_authentication
  skip_before_action :preload_subscription

  before_action :set_context

  def show
    load_invitation_state
  end

  def create
    result = ProjectInvitations::Accept.call(
      token_id: @context.fetch(:token_id),
      proof: identity_proof
    )

    if result.success?
      replace_current_session_with(result.user)
      clear_authentication_link_context
      redirect_to project_path(result.project), notice: "You've joined \"#{result.project.name}\"!"
      return
    end

    clear_authentication_link_context if terminal_status?(result.status)
    @acceptance_status = result.status
    @invitation = result.invitation
    @result_errors = result.errors
    recover_invitation_state
    prepare_invitation_state
    render :show, status: response_status(@acceptance_status)
  end

  private

  def set_context
    @context = authentication_link_context(:invitation)
    return if @context

    @acceptance_status = :invalid
    render :show, status: :unprocessable_content
  end

  def load_invitation_state
    resolution = resolver.revalidate(
      token_id: @context.fetch(:token_id),
      expected_purpose: :invitation
    )
    @acceptance_status = resolution.status
    @invitation = resolution.token&.project_invitation
    clear_authentication_link_context if terminal_status?(@acceptance_status)
    prepare_invitation_state
  end

  def prepare_invitation_state
    return unless @invitation

    @existing_user = User.find_by(email: @invitation.email)
    @matching_session = Current.user && Current.user.email == @invitation.email
    @mismatched_session = Current.user && !@matching_session
    @oauth_providers = Screenote::Deployment.current.social_oauth_providers
  end

  def recover_invitation_state
    return if @invitation || terminal_status?(@acceptance_status)

    resolution = resolver.revalidate(
      token_id: @context.fetch(:token_id),
      expected_purpose: :invitation
    )
    if resolution.valid?
      @invitation = resolution.token.project_invitation
    else
      @acceptance_status = resolution.status
      clear_authentication_link_context
    end
  end

  def identity_proof
    method = acceptance_params[:method]
    return ProjectInvitations::IdentityProof.session(user: Current.user) if method == "session" && Current.user
    return unless method == "local"

    ProjectInvitations::IdentityProof.local(
      password: acceptance_params[:password],
      password_confirmation: acceptance_params[:password_confirmation]
    )
  end

  def acceptance_params
    @acceptance_params ||= params
      .fetch(:acceptance, ActionController::Parameters.new)
      .permit(:method, :password, :password_confirmation)
  end

  def resolver
    @resolver ||= AuthenticationLinks::Resolver.new(keyring: AuthenticationLinks::Runtime.keyring)
  end

  def terminal_status?(status)
    %i[invalid expired cancelled already_used superseded issuer_revoked].include?(status)
  end

  def response_status(status)
    %i[retryable_busy unavailable].include?(status) ? :service_unavailable : :unprocessable_content
  end
end
