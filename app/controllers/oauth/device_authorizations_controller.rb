# frozen_string_literal: true

module Oauth
  class DeviceAuthorizationsController < ApplicationController
    VERIFICATION_ATTEMPT_LIMIT = 10
    VERIFICATION_ATTEMPT_WINDOW = 15.minutes
    RATE_LIMITER_RETRY_AFTER = 60

    layout "auth"

    before_action :enforce_verification_rate_limit, only: %i[show update], if: -> { params[:user_code].present? }
    before_action :find_device_grant, only: %i[show update], if: -> { params[:user_code].present? }
    rescue_from DeviceAuthorizationRateLimiter::Unavailable, with: :render_rate_limiter_unavailable

    def show
      render :enter_code unless params[:user_code].present?
    end

    def update
      return render_invalid_decision unless params[:decision].in?(%w[approve deny])
      return unless @device_grant

      decision = params[:decision]
      @device_grant.with_lock do
        unless authorizable?(@device_grant)
          return render_invalid_code
        end

        attributes = { resource_owner: Current.user }
        attributes[decision == "approve" ? :approved_at : :denied_at] = Time.current
        @device_grant.update!(attributes)
      end

      render decision == "approve" ? :approved : :denied
    end

    private

    def find_device_grant
      normalized_code = OauthDeviceGrant.normalize_user_code(params[:user_code])
      @device_grant = OauthDeviceGrant.find_by(user_code: normalized_code) if normalized_code
      render_invalid_code unless authorizable?(@device_grant)
    end

    def authorizable?(grant)
      grant.present? && !grant.expired? && !grant.approved? && !grant.denied?
    end

    def enforce_verification_rate_limit
      render_verification_rate_limited if verification_rate_limited?
    end

    def render_invalid_code
      @device_grant = nil
      render :invalid_code, status: :unprocessable_entity
    end

    def verification_rate_limited?
      DeviceAuthorizationRateLimiter.exceeded?(
        bucket: :verification,
        identity: "#{Current.user.id}:#{request.remote_ip}",
        limit: VERIFICATION_ATTEMPT_LIMIT,
        within: VERIFICATION_ATTEMPT_WINDOW
      )
    end

    def render_verification_rate_limited
      response.set_header("Retry-After", VERIFICATION_ATTEMPT_WINDOW.to_i.to_s)
      render :rate_limited, status: :too_many_requests
    end

    def render_rate_limiter_unavailable(_error)
      Rails.logger.warn("OAuth device verification rate limiter unavailable")
      response.set_header("Retry-After", RATE_LIMITER_RETRY_AFTER.to_s)
      response.set_header("Cache-Control", "no-store")
      response.set_header("Pragma", "no-cache")
      render :temporarily_unavailable, status: :service_unavailable
    end

    def render_invalid_decision
      render plain: "Choose Approve or Deny.", status: :unprocessable_entity
    end
  end
end
