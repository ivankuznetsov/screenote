# frozen_string_literal: true

require "digest"

class BootstrapController < ApplicationController
  RATE_LIMIT = 5
  RATE_LIMIT_WINDOW = 1.hour
  RATE_LIMIT_RETRY_AFTER = 60
  BOOTSTRAP_RATE_LIMIT_STORE = Screenote::RateLimitStore.new(store: -> { cache_store })

  layout "auth"

  skip_before_action :require_authentication
  before_action :set_bootstrap_security_headers
  before_action :require_self_hosted_bootstrap
  rate_limit to: RATE_LIMIT,
    within: RATE_LIMIT_WINDOW,
    by: :bootstrap_ip_rate_limit_identity,
    with: :render_rate_limited,
    store: BOOTSTRAP_RATE_LIMIT_STORE,
    name: "ip",
    only: :create
  rate_limit to: RATE_LIMIT,
    within: RATE_LIMIT_WINDOW,
    by: :bootstrap_email_rate_limit_identity,
    with: :render_rate_limited,
    store: BOOTSTRAP_RATE_LIMIT_STORE,
    name: "email",
    only: :create

  rescue_from Screenote::RateLimitStore::Unavailable, with: :render_rate_limiter_unavailable

  def show
    prepare_form
  end

  def create
    attributes = bootstrap_params
    result = Installations::Claim.call(
      email: attributes[:email],
      password: attributes[:password],
      password_confirmation: attributes[:password_confirmation],
      channel: "web"
    )

    case result.status
    when :claimed
      replace_current_session_with(result.user)
      redirect_to dashboard_path, notice: "Screenote is ready. Your administrator account has been created."
    when :already_claimed
      redirect_after_claim
    when :email_taken, :invalid
      prepare_form(email: attributes[:email], errors: result.errors)
      render :show, status: :unprocessable_content
    when :retryable_busy
      render_temporarily_unavailable("Setup is busy. Please retry in a moment.")
    else
      render_temporarily_unavailable("Setup is temporarily unavailable.")
    end
  end

  private

  def set_bootstrap_security_headers
    response.set_header("Cache-Control", "no-store")
    response.set_header("Pragma", "no-cache")
    response.set_header("Referrer-Policy", "no-referrer")
    response.set_header("X-Robots-Tag", "noindex, nofollow")
  end

  def require_self_hosted_bootstrap
    installation = Installation.current
    return not_found unless Screenote::Deployment.current.self_hosted? && installation&.self_hosted?
    return unless installation.claimed?

    redirect_after_claim
  end

  def redirect_after_claim
    redirect_to(Current.user ? dashboard_path : new_session_path)
  end

  def prepare_form(email: nil, errors: {})
    @email = AdmissionLock.normalize(email)
    @errors = errors
  rescue ArgumentError
    @email = email.to_s.strip
    @errors = errors
  end

  def bootstrap_params
    params
      .fetch(:bootstrap, ActionController::Parameters.new)
      .permit(:email, :password, :password_confirmation)
  end

  def bootstrap_ip_rate_limit_identity
    Digest::SHA256.hexdigest(request.remote_ip.to_s)
  end

  def bootstrap_email_rate_limit_identity
    normalized_email = AdmissionLock.normalize(params.dig(:bootstrap, :email))
    Digest::SHA256.hexdigest(normalized_email)
  rescue ArgumentError
    Digest::SHA256.hexdigest("")
  end

  def render_rate_limited
    response.set_header("Retry-After", RATE_LIMIT_WINDOW.to_i.to_s)
    prepare_form(email: params.dig(:bootstrap, :email), errors: { base: [ "Too many setup attempts. Please retry later." ] })
    render :show, status: :too_many_requests
  end

  def render_rate_limiter_unavailable(_error)
    render_temporarily_unavailable("Setup is temporarily unavailable.")
  end

  def render_temporarily_unavailable(message)
    response.set_header("Retry-After", RATE_LIMIT_RETRY_AFTER.to_s)
    prepare_form(email: params.dig(:bootstrap, :email), errors: { base: [ message ] })
    render :show, status: :service_unavailable
  end
end
