# frozen_string_literal: true

require "test_helper"

class AuthenticationLinksControllerTest < ActionDispatch::IntegrationTest
  setup do
    @rate_limit_backend = ActiveSupport::Cache::MemoryStore.new
    ActionController::Base.cache_store = @rate_limit_backend
    @user = users(:alice)
    @issued = nil
    AuthenticationToken.transaction do
      locked_user = User.lock.find(@user.id)
      @issued = AuthenticationLinks::Issuer.new(
        origin: AuthenticationLinks::Runtime.origin,
        keyring: AuthenticationLinks::Runtime.keyring
      ).call(
        purpose: :password_reset,
        subject: locked_user,
        expires_at: 15.minutes.from_now
      )
    end
  end

  test "GET is a sterile local-only exchange page" do
    assert_no_difference [ "AuthenticationToken.count", "Session.count" ] do
      get authentication_link_path(:password_reset), params: { token: "ignored-query-value" }
    end

    assert_response :success
    assert_security_headers
    assert_select "form[action='#{exchange_authentication_link_path(:password_reset)}'][method='post']"
    assert_select "script[src^='http']", count: 0
    assert_select "link[href^='http']", count: 0
    assert_not_includes response.body, "ignored-query-value"
  end

  test "POST resolves the body credential and stores only token id and purpose" do
    raw = @issued.presentation.fragment

    post exchange_authentication_link_path(:password_reset), params: { token: raw }

    assert_redirected_to edit_password_path
    assert_equal(
      { "token_id" => @issued.token.id, "purpose" => "password_reset" },
      session[:authentication_link]
    )
    assert_not_includes response.location, raw
    assert_not_includes response.body, raw
    assert_not_includes cookies.to_s, raw
    assert @issued.token.reload.outstanding?
  end

  test "wrong purpose and malformed credentials fail without retaining context" do
    post exchange_authentication_link_path(:magic_link), params: { token: @issued.presentation.fragment }

    assert_response :unprocessable_content
    assert_nil session[:authentication_link]
    assert @issued.token.reload.outstanding?
  end

  test "a failed exchange clears previously stored context" do
    post exchange_authentication_link_path(:password_reset), params: { token: @issued.presentation.fragment }
    assert_equal @issued.token.id, session.dig(:authentication_link, "token_id")

    post exchange_authentication_link_path(:password_reset), params: { token: "malformed" }

    assert_response :unprocessable_content
    assert_nil session[:authentication_link]
    assert_select "[role='alert']", text: /invalid or has expired/i
  end

  test "invitation exchange remains available when deployment mail is disabled" do
    invitation = projects(:alice_project).project_invitations.create!(
      inviter: users(:alice),
      email: "auth-link-#{SecureRandom.hex(6)}@example.test"
    )
    issued = nil
    ProjectInvitation.transaction do
      issued = AuthenticationLinks::Issuer.new(
        origin: AuthenticationLinks::Runtime.origin,
        keyring: AuthenticationLinks::Runtime.keyring
      ).call(
        purpose: :invitation,
        subject: ProjectInvitation.lock.find(invitation.id),
        expires_at: 15.minutes.from_now
      )
    end
    deployment = mail_disabled_deployment

    with_singleton_method(Screenote::Deployment, :current, -> { deployment }) do
      post exchange_authentication_link_path(:invitation), params: { token: issued.presentation.fragment }
      assert_redirected_to invitation_acceptance_path

      get authentication_link_path(:password_reset)
      assert_response :not_found
    end
  end

  test "purpose must be enabled for the current deployment" do
    get authentication_link_path(:account_recovery)
    assert_response :not_found

    post exchange_authentication_link_path(:account_recovery), params: { token: @issued.presentation.fragment }
    assert_response :not_found
    assert_nil session[:authentication_link]
  end

  test "every token purpose has an explicit destination route" do
    assert_equal(
      AuthenticationToken.purposes.keys.sort,
      AuthenticationLinksController::DESTINATION_ROUTES.keys.sort
    )
  end

  test "exchange rate limiting is bounded and retryable" do
    10.times do
      post exchange_authentication_link_path(:password_reset), params: { token: "malformed" }
      assert_response :unprocessable_content
    end

    post exchange_authentication_link_path(:password_reset), params: { token: "malformed" }

    assert_response :too_many_requests
    assert_equal 15.minutes.to_i.to_s, response.headers["Retry-After"]
    assert_nil session[:authentication_link]
  end

  test "exchange fails closed when the rate-limit backend is unavailable" do
    unavailable = ->(*, **) { raise IOError, "offline" }

    with_singleton_method(@rate_limit_backend, :increment, unavailable) do
      post exchange_authentication_link_path(:password_reset), params: { token: @issued.presentation.fragment }
    end

    assert_response :service_unavailable
    assert_equal "60", response.headers["Retry-After"]
    assert_includes response.headers.fetch("Cache-Control"), "no-store"
    assert_nil session[:authentication_link]
    assert @issued.token.reload.outstanding?
  end

  test "transient database failures return a retryable exchange response" do
    resolver = Object.new
    resolver.define_singleton_method(:resolve) do |**|
      raise ActiveRecord::ConnectionNotEstablished, "database unavailable"
    end

    with_singleton_method(AuthenticationLinks::Resolver, :new, ->(**) { resolver }) do
      post exchange_authentication_link_path(:password_reset),
        params: { token: @issued.presentation.fragment }
    end

    assert_response :service_unavailable
    assert_equal "60", response.headers["Retry-After"]
    assert_security_headers
    assert_empty response.body
    assert_not_includes cookies.to_s, @issued.presentation.fragment
    assert @issued.token.reload.outstanding?
  end

  private

  def assert_security_headers
    assert_includes response.headers.fetch("Cache-Control"), "no-store"
    assert_equal "no-referrer", response.headers["Referrer-Policy"]
    assert_equal "noindex, nofollow", response.headers["X-Robots-Tag"]
  end

  def mail_disabled_deployment
    Screenote::Deployment.new(
      {
        "SCREENOTE_EDITION" => "self_hosted",
        "SCREENOTE_BASE_URL" => "http://screenote.internal",
        "SCREENOTE_BOOTSTRAP_TOKEN" => "b" * 43
      },
      production: false
    )
  end


  def with_singleton_method(object, name, implementation)
    original = object.method(name)
    object.define_singleton_method(name, implementation)
    yield
  ensure
    object.define_singleton_method(name, original) if original
  end
end
