# frozen_string_literal: true

module Oauth
  class DeviceAuthorizationRequestsController < ActionController::API
    USER_CODE_ALPHABET = "23456789ABCDEFGHJKMNPQRSTUVWXYZ"
    INITIATION_LIMIT = 20
    INITIATION_WINDOW = 1.minute
    RATE_LIMITER_RETRY_AFTER = 60

    after_action :prevent_caching
    rescue_from DeviceAuthorizationRateLimiter::Unavailable, with: :render_rate_limiter_unavailable

    def create
      return render_rate_limited if initiation_rate_limited?

      application = public_application
      return render_oauth_error(:invalid_client, status: :unauthorized) unless application

      scopes = requested_scopes(application)
      return render_oauth_error(:invalid_scope) unless scopes

      plaintext_device_code = SecureRandom.urlsafe_base64(32)
      grant = OauthDeviceGrant.create!(
        application: application,
        device_code: OauthDeviceGrant.digest_device_code(plaintext_device_code),
        user_code: generate_user_code,
        scopes: scopes.to_s,
        expires_at: OauthDeviceGrant::DEFAULT_EXPIRES_IN.seconds.from_now,
        polling_interval: OauthDeviceGrant::DEFAULT_POLLING_INTERVAL
      )

      render json: authorization_response(grant, plaintext_device_code)
    end

    private

    def public_application
      application = Doorkeeper::Application.by_uid(params[:client_id])
      application unless application&.confidential?
    end

    def requested_scopes(application)
      scope_string = params[:scope].presence || Doorkeeper.config.default_scopes.to_s
      valid = Doorkeeper::OAuth::Helpers::ScopeChecker.valid?(
        scope_str: scope_string,
        server_scopes: Doorkeeper.config.scopes,
        app_scopes: application.scopes,
        grant_type: ScreenoteOauth::DeviceCodeGrant::GRANT_TYPE
      )

      Doorkeeper::OAuth::Scopes.from_string(scope_string) if valid
    end

    def generate_user_code
      loop do
        characters = SecureRandom.alphanumeric(10, chars: USER_CODE_ALPHABET.chars)
        code = "#{characters.first(5)}-#{characters.last(5)}"
        return code unless OauthDeviceGrant.exists?(user_code: code)
      end
    end

    def authorization_response(grant, plaintext_device_code)
      {
        device_code: plaintext_device_code,
        user_code: grant.user_code,
        verification_uri: oauth_device_url(Screenote::Deployment.current.url_options),
        verification_uri_complete: oauth_device_url(
          Screenote::Deployment.current.url_options.merge(user_code: grant.user_code)
        ),
        expires_in: OauthDeviceGrant::DEFAULT_EXPIRES_IN,
        interval: grant.polling_interval
      }
    end

    def initiation_rate_limited?
      DeviceAuthorizationRateLimiter.exceeded?(
        bucket: :initiation,
        identity: request.remote_ip,
        limit: INITIATION_LIMIT,
        within: INITIATION_WINDOW
      )
    end

    def render_rate_limited
      response.set_header("Retry-After", INITIATION_WINDOW.to_i.to_s)
      render_oauth_error(:temporarily_unavailable, status: :too_many_requests)
    end

    def render_rate_limiter_unavailable(_error)
      Rails.logger.warn("OAuth device authorization rate limiter unavailable")
      response.set_header("Retry-After", RATE_LIMITER_RETRY_AFTER.to_s)
      prevent_caching
      render_oauth_error(:temporarily_unavailable, status: :service_unavailable)
    end

    def render_oauth_error(error, status: :bad_request)
      render json: { error: error }, status: status
    end

    def prevent_caching
      response.set_header("Cache-Control", "no-store")
      response.set_header("Pragma", "no-cache")
    end
  end
end
