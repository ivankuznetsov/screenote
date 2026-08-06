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
      if params[:user_code].present?
        load_principal_projects
        @selected_principal_project_id = nil
      else
        render :enter_code
      end
    end

    def update
      return render_invalid_decision unless params[:decision].in?(%w[approve deny])
      return render_invalid_code unless @device_grant

      decision = params[:decision]
      return unless persist_decision(decision)

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

    def persist_decision(decision)
      return persist_denial if decision == "deny"

      DynamicClientAuthorizationQuota.authorize(user: Current.user, application: @device_grant.application) do
        persist_approval
      end
    rescue DynamicClientAuthorizationQuota::Exceeded => error
      render_dynamic_client_quota_exceeded(error)
      false
    end

    def persist_approval
      selected_project_id = params[:principal_project_id].presence
      if selected_project_id
        persist_project_approval(selected_project_id)
      else
        persist_account_approval
      end
    end

    def persist_account_approval
      PrincipalBinding.with_locked_user(user: Current.user, credential: @device_grant) do |valid, locked_user|
        unless valid && authorizable?(@device_grant)
          render_invalid_code
          next false
        end

        @device_grant.update!(
          resource_owner: locked_user,
          principal_kind: "user",
          project: nil,
          approved_at: Time.current
        )
        true
      end
    end

    def persist_project_approval(project_id)
      PrincipalBinding.with_locked_project(user: Current.user, project_id: project_id, credential: @device_grant) do |valid|
        unless valid
          render_invalid_principal_selection
          next false
        end

        unless authorizable?(@device_grant)
          render_invalid_code
          next false
        end

        @device_grant.update!(
          resource_owner: Current.user,
          principal_kind: "project",
          project_id: project_id,
          approved_at: Time.current
        )
        true
      end
    end

    def persist_denial
      @device_grant.with_lock do
        unless authorizable?(@device_grant)
          render_invalid_code
          next false
        end

        @device_grant.update!(resource_owner: Current.user, denied_at: Time.current)
        true
      end
    end

    def render_invalid_principal_selection
      load_principal_projects
      @selected_principal_project_id = nil
      @principal_selection_error = "Choose your account or a project you currently belong to."
      render :show, status: :unprocessable_entity
    end

    def render_dynamic_client_quota_exceeded(error)
      load_principal_projects
      @selected_principal_project_id = nil
      @principal_selection_error = error.message
      render :show, status: :unprocessable_entity
    end

    def load_principal_projects
      @principal_projects = Current.user.projects.order(:name, :id)
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
