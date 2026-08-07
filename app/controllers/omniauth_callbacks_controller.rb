# frozen_string_literal: true

class OmniauthCallbacksController < ApplicationController
  INVITATION_TERMINAL_STATUSES = %i[
    invalid expired cancelled already_used superseded issuer_revoked
  ].freeze

  skip_before_action :require_authentication
  skip_before_action :preload_subscription

  def create
    auth_hash = request.env["omniauth.auth"]
    provider = params[:provider].to_s

    unless provider_enabled?(provider, auth_hash)
      redirect_to new_session_path, alert: "OAuth provider not enabled."
      return
    end

    context = authentication_link_context(:invitation)
    if invitation_oauth_intent?
      if context
        accept_invitation_with_provider(context, auth_hash)
      else
        redirect_to invitation_acceptance_path, alert: "This invitation can no longer be accepted."
      end
    else
      clear_authentication_link_context if context
      sign_in_with_provider(auth_hash, provider)
    end
  end

  def failure
    Rails.logger.warn("OAuth authentication failed")
    redirect_to new_session_path, alert: "Authentication failed. Please try again."
  end

  private

  def provider_enabled?(provider, auth_hash)
    identity = User.verified_oauth_identity(auth_hash)
    identity&.provider == provider && RailsSimpleAuth.configuration.oauth_provider_enabled?(provider)
  end

  def invitation_oauth_intent?
    request.env["omniauth.origin"] == invitation_acceptance_path
  end

  def sign_in_with_provider(auth_hash, provider)
    user = User.authenticate_verified_oauth(
      auth_hash,
      allow_create: Screenote::Deployment.current.saas?
    )
    display_name = RailsSimpleAuth.configuration.oauth_provider_display_name(provider)

    unless user&.persisted? && user.access_active?
      redirect_to new_session_path, alert: "Could not authenticate with #{display_name}."
      return
    end

    replace_current_session_with(user)
    run_after_sign_in_callback(user)
    redirect_to stored_location_or_default,
      notice: "Signed in successfully with #{display_name}."
  end

  def accept_invitation_with_provider(context, auth_hash)
    proof = ProjectInvitations::IdentityProof.provider(auth_hash)
    result = ProjectInvitations::Accept.call(
      token_id: context.fetch(:token_id),
      proof: proof
    )

    if result.success?
      clear_authentication_link_context
      replace_current_session_with(result.user)
      redirect_to project_path(result.project), notice: "You've joined \"#{result.project.name}\"!"
      return
    end

    clear_authentication_link_context if INVITATION_TERMINAL_STATUSES.include?(result.status)
    redirect_to invitation_acceptance_path, alert: invitation_error(result.status)
  end

  def invitation_error(status)
    case status
    when :identity_mismatch then "That provider account does not match the invited email."
    when :invalid_identity then "That provider did not verify the invited email."
    when :limit_reached then "This project has reached its member limit."
    when :retryable_busy then "Screenote is busy. Please try again."
    else "This invitation can no longer be accepted."
    end
  end
end
