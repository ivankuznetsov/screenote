# frozen_string_literal: true

require "digest"

class AccountRecoveriesController < ApplicationController
  RATE_LIMIT = 5
  RATE_LIMIT_WINDOW = 15.minutes
  RATE_LIMIT_RETRY_AFTER = 60
  RECOVERY_RATE_LIMIT_STORE = Screenote::RateLimitStore.new(store: -> { cache_store })

  layout "auth"

  skip_before_action :require_authentication
  skip_before_action :preload_subscription
  before_action :set_private_headers
  rate_limit to: RATE_LIMIT,
    within: RATE_LIMIT_WINDOW,
    by: :recovery_ip_identity,
    with: :render_rate_limited,
    store: RECOVERY_RATE_LIMIT_STORE,
    name: "ip",
    only: :create
  rate_limit to: RATE_LIMIT,
    within: RATE_LIMIT_WINDOW,
    by: :recovery_token_identity,
    with: :render_rate_limited,
    store: RECOVERY_RATE_LIMIT_STORE,
    name: "token",
    only: :create

  rescue_from Screenote::RateLimitStore::Unavailable, with: :render_rate_limiter_unavailable

  def show
    context = recovery_context
    return render_unavailable_context unless context

    validation = AccountRecoveries::Validate.call(token_id: context.fetch(:token_id))
    if validation.status == :valid
      @account_email = validation.user.email
      @errors = {}
    elsif validation.status == :retryable_busy || validation.status == :unavailable
      render_temporarily_unavailable
    else
      clear_authentication_link_context
      render_unavailable_context
    end
  end

  def create
    context = recovery_context
    return render_unavailable_context unless context

    attributes = recovery_params
    result = AccountRecoveries::Consume.call(
      token_id: context.fetch(:token_id),
      password: attributes[:password],
      password_confirmation: attributes[:password_confirmation]
    )

    case result.status
    when :recovered
      clear_authentication_link_context
      replace_current_session_with(result.user)
      redirect_to dashboard_path, notice: "Local password updated. Other sessions and credentials were revoked."
    when :invalid
      validation = AccountRecoveries::Validate.call(token_id: context.fetch(:token_id))
      if validation.status == :valid
        @account_email = validation.user.email
        @errors = result.errors
        render :show, status: :unprocessable_content
      elsif validation.status == :retryable_busy || validation.status == :unavailable
        render_temporarily_unavailable
      else
        clear_authentication_link_context
        render_unavailable_context
      end
    when :retryable_busy, :unavailable
      render_temporarily_unavailable
    else
      clear_authentication_link_context
      render_unavailable_context
    end
  end

  private

  def recovery_context
    authentication_link_context(:account_recovery)
  end

  def recovery_params
    params
      .fetch(:account_recovery, ActionController::Parameters.new)
      .permit(:password, :password_confirmation)
  end

  def render_unavailable_context
    @account_email = nil
    @errors = { base: [ "This recovery link is invalid, expired, or already used." ] }
    render :show, status: :unprocessable_content
  end

  def render_temporarily_unavailable
    response.set_header("Retry-After", RATE_LIMIT_RETRY_AFTER.to_s)
    @account_email = nil
    @errors = { base: [ "Recovery is temporarily unavailable. Please retry." ] }
    render :show, status: :service_unavailable
  end

  def render_rate_limited
    response.set_header("Retry-After", RATE_LIMIT_WINDOW.to_i.to_s)
    @account_email = nil
    @errors = { base: [ "Too many recovery attempts. Please retry later." ] }
    render :show, status: :too_many_requests
  end

  def render_rate_limiter_unavailable(_error)
    render_temporarily_unavailable
  end

  def recovery_ip_identity
    Digest::SHA256.hexdigest(request.remote_ip.to_s)
  end

  def recovery_token_identity
    token_id = recovery_context&.fetch(:token_id, nil)
    Digest::SHA256.hexdigest(token_id.to_s)
  end

  def set_private_headers
    response.set_header("Cache-Control", "no-store, max-age=0")
    response.set_header("Pragma", "no-cache")
    response.set_header("Referrer-Policy", "no-referrer")
    response.set_header("X-Robots-Tag", "noindex, nofollow")
  end
end
