# frozen_string_literal: true

class AuthenticationLinksController < ApplicationController
  RATE_LIMIT = 10
  RATE_LIMIT_WINDOW = 15.minutes
  RATE_LIMITER_RETRY_AFTER = 60
  AUTHENTICATION_LINK_RATE_LIMIT_STORE = Screenote::RateLimitStore.new(store: -> { cache_store })
  DESTINATION_ROUTES = {
    "invitation" => :invitation_acceptance_path,
    "password_reset" => :edit_password_path,
    "magic_link" => :magic_link_path,
    "email_confirmation" => :confirmation_path,
    "account_recovery" => :account_recovery_path
  }.freeze
  PURPOSES = DESTINATION_ROUTES.keys.freeze
  TERMINAL_STATUSES = %i[invalid expired already_used superseded cancelled].freeze

  skip_before_action :require_authentication
  skip_before_action :preload_subscription
  before_action :set_purpose
  before_action :set_private_headers

  layout "authentication_link"

  rate_limit to: RATE_LIMIT, within: RATE_LIMIT_WINDOW, by: -> { client_ip }, only: :exchange,
    with: :render_rate_limited, store: AUTHENTICATION_LINK_RATE_LIMIT_STORE

  rescue_from Screenote::RateLimitStore::Unavailable, with: :render_rate_limiter_unavailable

  def show
  end

  def exchange
    clear_authentication_link_context
    result = resolver.resolve(credential: params[:token].to_s, expected_purpose: @purpose)

    if result.valid?
      store_authentication_link_context(token_id: result.token.id, purpose: @purpose)
      redirect_to destination_for(@purpose), status: :see_other
    else
      render :show, status: :unprocessable_content,
        locals: { exchange_error: "This authentication link is invalid or has expired." }
    end
  rescue ActiveRecord::ActiveRecordError => error
    Rails.logger.warn("Authentication link exchange temporarily unavailable (#{error.class})")
    render_exchange_unavailable
  end

  private

  def set_purpose
    @purpose = params[:purpose].to_s
    head :not_found unless PURPOSES.include?(@purpose) && purpose_available?(@purpose)
  end

  def purpose_available?(purpose)
    case purpose
    when "invitation"
      true
    when "account_recovery"
      Screenote::Deployment.current.self_hosted?
    else
      Screenote::Deployment.current.mail?
    end
  end

  def resolver
    @resolver ||= AuthenticationLinks::Resolver.new(keyring: AuthenticationLinks::Runtime.keyring)
  end

  def destination_for(purpose)
    public_send(DESTINATION_ROUTES.fetch(purpose))
  end

  def render_rate_limited
    response.set_header("Retry-After", RATE_LIMIT_WINDOW.to_i.to_s)
    head :too_many_requests
  end

  def render_rate_limiter_unavailable(_error)
    render_exchange_unavailable
  end

  def render_exchange_unavailable
    response.set_header("Retry-After", RATE_LIMITER_RETRY_AFTER.to_s)
    response.set_header("Cache-Control", "no-store")
    response.set_header("Pragma", "no-cache")
    head :service_unavailable
  end

  def set_private_headers
    response.headers["Cache-Control"] = "no-store, max-age=0"
    response.headers["Pragma"] = "no-cache"
    response.headers["Referrer-Policy"] = "no-referrer"
    response.headers["X-Robots-Tag"] = "noindex, nofollow"
  end
end
