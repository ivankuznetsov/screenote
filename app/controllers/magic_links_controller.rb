# frozen_string_literal: true

require "digest"

class MagicLinksController < ApplicationController
  RATE_LIMIT = 3
  RATE_LIMIT_WINDOW = 10.minutes
  RATE_LIMITER_RETRY_AFTER = 60
  RATE_LIMIT_DOMAIN = "screenote:magic-link-request:v1\0"
  MAGIC_LINK_RATE_LIMIT_STORE = Screenote::RateLimitStore.new(store: -> { cache_store })

  skip_before_action :require_authentication
  before_action :require_mail
  before_action :set_private_headers, only: :show
  layout "auth"

  rate_limit to: RATE_LIMIT, within: RATE_LIMIT_WINDOW,
    by: -> { self.class.rate_limit_identity(params[:email]) }, only: :create,
    with: -> { redirect_to magic_link_form_path, alert: "Too many magic link requests. Please try again later." },
    store: MAGIC_LINK_RATE_LIMIT_STORE

  rescue_from Screenote::RateLimitStore::Unavailable, with: :render_rate_limiter_unavailable

  def self.rate_limit_identity(email)
    Digest::SHA256.hexdigest("#{RATE_LIMIT_DOMAIN}#{email.to_s.strip.downcase}")
  end

  def new
    return redirect_to dashboard_path if permanent_user_signed_in?

    store_referrer_for_redirect
  end

  def create
    user = User.find_by_email(params[:email])
    UserAuthenticationLinks::Issue.call(user: user, purpose: :magic_link) if user

    redirect_to new_session_path, notice: "If an active account exists with that email, a magic link has been sent."
  end

  def show
    context = authentication_link_context(:magic_link)
    return invalid_link unless context

    result = UserAuthenticationLinks::Consume.call(
      token_id: context.fetch(:token_id),
      purpose: :magic_link
    )

    if result.consumed?
      clear_authentication_link_context
      replace_current_session_with(result.user)
      run_after_sign_in_callback(result.user)
      UserMailer.welcome(result.user).deliver_later if result.newly_confirmed
      redirect_to stored_location_or_default, notice: "Signed in successfully."
    elsif %i[retryable_busy unavailable].include?(result.status)
      redirect_to magic_link_path, alert: "Screenote is busy. Please try again."
    else
      clear_authentication_link_context
      invalid_link
    end
  end

  private

  def invalid_link
    redirect_to new_session_path, alert: "Invalid or expired magic link."
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
