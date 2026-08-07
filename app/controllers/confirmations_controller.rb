# frozen_string_literal: true

class ConfirmationsController < ApplicationController
  RATE_LIMIT = 3
  RATE_LIMIT_WINDOW = 1.hour
  RATE_LIMITER_RETRY_AFTER = 60
  CONFIRMATION_RATE_LIMIT_STORE = Screenote::RateLimitStore.new(store: -> { cache_store })

  skip_before_action :require_authentication
  before_action :require_mail
  before_action :set_private_headers, only: :show
  layout "auth"

  rate_limit to: RATE_LIMIT, within: RATE_LIMIT_WINDOW, by: -> { client_ip }, only: :create,
    with: -> { redirect_to new_confirmation_path, alert: "Too many confirmation requests. Please try again later." },
    store: CONFIRMATION_RATE_LIMIT_STORE

  rescue_from Screenote::RateLimitStore::Unavailable, with: :render_rate_limiter_unavailable

  def new
  end

  def create
    user = User.find_by_email(params[:email])
    if user&.unconfirmed_or_reconfirming?
      UserAuthenticationLinks::Issue.call(user: user, purpose: :email_confirmation)
    end

    redirect_to new_session_path,
      notice: "If an unconfirmed active account exists with that email, confirmation instructions have been sent."
  end

  def show
    context = authentication_link_context(:email_confirmation)
    return invalid_link unless context

    result = UserAuthenticationLinks::Consume.call(
      token_id: context.fetch(:token_id),
      purpose: :email_confirmation
    )

    if result.consumed?
      clear_authentication_link_context
      RailsSimpleAuth.configuration.after_confirmation_callback&.call(result.user, self)
      redirect_to new_session_path, notice: "Email confirmed! You can now sign in."
    elsif %i[retryable_busy unavailable].include?(result.status)
      redirect_to confirmation_path, alert: "Screenote is busy. Please try again."
    else
      clear_authentication_link_context
      invalid_link
    end
  end

  private

  def invalid_link
    redirect_to new_confirmation_path, alert: "Invalid or expired confirmation link."
  end

  def render_rate_limiter_unavailable(_error)
    response.set_header("Retry-After", RATE_LIMITER_RETRY_AFTER.to_s)
    response.set_header("Cache-Control", "no-store")
    response.set_header("Pragma", "no-cache")
    head :service_unavailable
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
