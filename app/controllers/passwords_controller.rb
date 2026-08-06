# frozen_string_literal: true

class PasswordsController < ApplicationController
  RATE_LIMIT = 3
  RATE_LIMIT_WINDOW = 1.hour
  RATE_LIMITER_RETRY_AFTER = 60
  PASSWORD_RATE_LIMIT_STORE = Screenote::RateLimitStore.new(store: -> { cache_store })

  skip_before_action :require_authentication
  before_action :require_mail
  before_action :set_private_headers, only: %i[edit update]
  layout "auth"

  rate_limit to: RATE_LIMIT, within: RATE_LIMIT_WINDOW, by: -> { client_ip }, only: :create,
    with: -> { redirect_to new_password_path, alert: "Too many password reset requests. Please try again later." },
    store: PASSWORD_RATE_LIMIT_STORE

  rescue_from Screenote::RateLimitStore::Unavailable, with: :render_rate_limiter_unavailable

  def new
  end

  def create
    user = User.find_by_email(params[:email])
    UserAuthenticationLinks::Issue.call(user: user, purpose: :password_reset) if user

    redirect_to new_session_path,
      notice: "If an active account exists with that email, password reset instructions have been sent."
  end

  def edit
    return if valid_context?

    clear_authentication_link_context
    redirect_invalid_context
  end

  def update
    context = authentication_link_context(:password_reset)
    return redirect_invalid_context unless context

    result = UserAuthenticationLinks::Consume.call(
      token_id: context.fetch(:token_id),
      purpose: :password_reset,
      attributes: password_params
    )

    case result.status
    when :consumed
      clear_authentication_link_context
      destroy_current_session if Current.user&.id == result.user.id
      redirect_to new_session_path, notice: "Password has been reset. Please sign in with your new password."
    when :validation_failed
      @errors = result.errors
      render :edit, status: :unprocessable_content
    when :retryable_busy, :unavailable
      redirect_to edit_password_path, alert: "Screenote is busy. Please try again."
    else
      clear_authentication_link_context
      redirect_invalid_context
    end
  end

  private

  def valid_context?
    context = authentication_link_context(:password_reset)
    return false unless context

    AuthenticationLinks::Resolver.new(keyring: AuthenticationLinks::Runtime.keyring)
      .revalidate(token_id: context.fetch(:token_id), expected_purpose: :password_reset)
      .valid?
  end

  def redirect_invalid_context
    redirect_to new_password_path, alert: "Invalid or expired password reset link."
  end

  def render_rate_limiter_unavailable(_error)
    response.set_header("Retry-After", RATE_LIMITER_RETRY_AFTER.to_s)
    response.set_header("Cache-Control", "no-store")
    response.set_header("Pragma", "no-cache")
    head :service_unavailable
  end

  def password_params
    params.expect(user: %i[password password_confirmation])
  end

  def require_mail
    head :not_found unless Screenote::Deployment.current.mail?
  end

  def set_private_headers
    response.headers["Cache-Control"] = "no-store, max-age=0"
    response.headers["Referrer-Policy"] = "no-referrer"
    response.headers["X-Robots-Tag"] = "noindex, nofollow"
  end
end
