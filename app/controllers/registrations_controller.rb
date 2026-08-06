# frozen_string_literal: true

class RegistrationsController < ApplicationController
  RATE_LIMIT = 5
  RATE_LIMIT_WINDOW = 1.hour
  RATE_LIMITER_RETRY_AFTER = 60
  REGISTRATION_RATE_LIMIT_STORE = Screenote::RateLimitStore.new(store: -> { cache_store })

  skip_before_action :require_authentication
  before_action :require_saas
  layout "auth"

  rate_limit to: RATE_LIMIT, within: RATE_LIMIT_WINDOW, by: -> { client_ip }, only: :create,
    with: -> { redirect_to sign_up_path, alert: "Too many sign up attempts. Please try again later." },
    store: REGISTRATION_RATE_LIMIT_STORE

  rescue_from Screenote::RateLimitStore::Unavailable, with: :render_rate_limiter_unavailable

  def new
    return redirect_to dashboard_path if user_signed_in?

    @user = User.new
  end

  def create
    @user = create_user
    return render(:new, status: :unprocessable_content) unless @user.persisted?

    run_after_sign_up_callback(@user)
    if Screenote::Deployment.current.mail?
      issuance = UserAuthenticationLinks::Issue.call(user: @user, purpose: :email_confirmation)
      if issuance.issued?
        redirect_to new_session_path, notice: "Account created! Please check your email to confirm your account."
      else
        redirect_to new_confirmation_path,
          alert: "Account created, but confirmation email could not be sent. Please request another."
      end
    else
      replace_current_session_with(@user)
      redirect_to dashboard_path, notice: "Account created successfully!"
    end
  rescue DatabaseRetry::Exhausted
    @user ||= User.new(registration_params)
    @user.errors.add(:base, "Screenote is busy. Please try again.")
    render :new, status: :service_unavailable
  end

  private

  def require_saas
    head :not_found unless Screenote::Deployment.current.saas?
  end

  def render_rate_limiter_unavailable(_error)
    response.set_header("Retry-After", RATE_LIMITER_RETRY_AFTER.to_s)
    response.set_header("Cache-Control", "no-store")
    response.set_header("Pragma", "no-cache")
    head :service_unavailable
  end

  def registration_params
    params.expect(user: %i[email password password_confirmation])
  end

  def create_user
    attributes = registration_params
    candidate = User.new(attributes)
    return candidate.tap(&:valid?) if attributes[:email].blank?

    DatabaseRetry.call do
      User.transaction do
        normalized_email = AdmissionLock.email!(attributes[:email])
        existing = User.where(email: normalized_email).order(:id).lock.first
        if existing
          candidate.email = normalized_email
          candidate.valid?
          candidate.errors.add(:email, "has already been taken") unless candidate.errors.added?(:email, :taken)
          candidate
        else
          candidate.email = normalized_email
          candidate.save
          candidate
        end
      end
    end
  end
end
