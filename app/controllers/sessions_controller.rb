# frozen_string_literal: true

class SessionsController < ApplicationController
  RATE_LIMIT = 5
  RATE_LIMIT_WINDOW = 15.minutes
  RATE_LIMITER_RETRY_AFTER = 60
  SESSION_RATE_LIMIT_STORE = Screenote::RateLimitStore.new(store: -> { cache_store })

  skip_before_action :require_authentication, only: %i[new create]
  layout "auth"

  rate_limit to: RATE_LIMIT, within: RATE_LIMIT_WINDOW, by: -> { client_ip }, only: :create,
    with: -> { redirect_to new_session_path, alert: "Too many login attempts. Please try again later." },
    store: SESSION_RATE_LIMIT_STORE

  rescue_from Screenote::RateLimitStore::Unavailable, with: :render_rate_limiter_unavailable

  def new
    return redirect_to dashboard_path if permanent_user_signed_in?

    store_referrer_for_redirect
  end

  def create
    user = User.authenticate_by(
      email: params[:email].to_s.strip.downcase,
      password: params[:password].to_s
    )

    if user&.access_active?
      if Screenote::Deployment.current.mail? && user.unconfirmed?
        @error_message = "Please confirm your email before signing in."
        @previous_email = params[:email]
        render :new, status: :unprocessable_content
      else
        replace_current_session_with(user)
        run_after_sign_in_callback(user)
        redirect_to after_sign_in_path, notice: "Signed in successfully."
      end
    else
      @error_message = "Invalid email or password"
      @previous_email = params[:email]
      render :new, status: :unprocessable_content
    end
  end

  def destroy
    user = current_user
    destination = authentication_link_context(:invitation) ? invitation_acceptance_path : root_path
    destroy_current_session
    run_after_sign_out_callback(user)
    redirect_to destination, notice: "Signed out successfully."
  end

  private

  def render_rate_limiter_unavailable(_error)
    response.set_header("Retry-After", RATE_LIMITER_RETRY_AFTER.to_s)
    response.set_header("Cache-Control", "no-store")
    response.set_header("Pragma", "no-cache")
    head :service_unavailable
  end

  def after_sign_in_path
    if authentication_link_context(:invitation)
      invitation_acceptance_path
    else
      stored_location_or_default
    end
  end
end
