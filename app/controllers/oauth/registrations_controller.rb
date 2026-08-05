# frozen_string_literal: true

module Oauth
  class RegistrationsController < ActionController::API
    RATE_LIMITER_RETRY_AFTER = 60

    wrap_parameters false
    before_action :require_registration_availability
    before_action :enforce_registration_rate_limit
    rescue_from DynamicClientRegistrationRateLimiter::Unavailable, with: :render_rate_limiter_unavailable

    # POST /oauth/register (RFC 7591 Dynamic Client Registration)
    def create
      result = DynamicClientRegistration.call(
        client_name: registration_params[:client_name],
        redirect_uris: registration_params[:redirect_uris],
        token_endpoint_auth_method: registration_params[:token_endpoint_auth_method],
        grant_types: registration_params[:grant_types]
      )

      render json: registration_response(result.application), status: result.created ? :created : :ok
    rescue DynamicClientRegistration::InvalidMetadata, ActiveRecord::RecordInvalid => error
      render_registration_error(error.message)
    rescue DynamicClientRegistration::CapacityExceeded => error
      render_registration_error(error.message, status: :service_unavailable)
    end

    private

    def require_registration_availability
      return if Screenote::Deployment.current.saas?
      return if Installation.current&.claimed?

      head :not_found
    end

    def enforce_registration_rate_limit
      return if performed?

      if DynamicClientRegistrationRateLimiter.exceeded?(identity: request.remote_ip)
        response.set_header("Retry-After", DynamicClientRegistrationRateLimiter::WINDOW.to_i.to_s)
        render_registration_error("Too many registration requests", status: :too_many_requests)
      end
    end

    def registration_response(application)
      {
        client_id: application.uid,
        client_name: application.name,
        redirect_uris: application.redirect_uri.split("\n"),
        grant_types: DynamicClientRegistration::SUPPORTED_GRANT_TYPES,
        token_endpoint_auth_method: "none",
        response_types: [ "code" ],
        client_id_issued_at: application.created_at.to_i,
        client_secret_expires_at: 0
      }
    end

    def render_rate_limiter_unavailable(_error)
      Rails.logger.warn("OAuth dynamic registration rate limiter unavailable")
      response.set_header("Retry-After", RATE_LIMITER_RETRY_AFTER.to_s)
      render_registration_error("Registration is temporarily unavailable", status: :service_unavailable)
    end

    def render_registration_error(message, status: :bad_request)
      response.set_header("Cache-Control", "no-store")
      response.set_header("Pragma", "no-cache")
      render json: { error: "invalid_client_metadata", error_description: message }, status: status
    end

    def registration_params
      params.permit(:client_name, :token_endpoint_auth_method, redirect_uris: [], grant_types: [])
    end
  end
end
