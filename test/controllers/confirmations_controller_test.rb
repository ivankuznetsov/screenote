# frozen_string_literal: true

require "test_helper"

class ConfirmationsControllerTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper
  self.use_transactional_tests = false

  setup do
    @rate_limit_backend = ActiveSupport::Cache::MemoryStore.new
    ActionController::Base.cache_store = @rate_limit_backend
    @user = User.create!(
      email: "confirmation-controller-#{SecureRandom.hex(6)}@example.test",
      password: "password123"
    )
    clear_enqueued_jobs
  end

  teardown do
    @user.destroy! if @user&.persisted?
    clear_enqueued_jobs
    Current.reset
  end

  test "new renders and create discloses neither missing nor confirmed accounts" do
    get new_confirmation_path
    assert_response :success

    failure = ->(**) { raise "ineligible users must not receive a link" }
    with_singleton_method(UserAuthenticationLinks::Issue, :call, failure) do
      post confirmations_path, params: { email: "missing-#{SecureRandom.hex(4)}@example.test" }
      assert_redirected_to new_session_path

      post confirmations_path, params: { email: users(:alice).email }
      assert_redirected_to new_session_path
    end

    assert_equal(
      "If an unconfirmed active account exists with that email, confirmation instructions have been sent.",
      flash[:notice]
    )
  end

  test "create issues confirmation only for an eligible account" do
    assert_difference -> { @user.authentication_tokens.email_confirmation.outstanding.count }, 1 do
      assert_enqueued_emails 1 do
        post confirmations_path, params: { email: @user.email.upcase }
      end
    end

    assert_redirected_to new_session_path
  end

  test "show rejects a missing context without revealing identity" do
    get confirmation_path

    assert_redirected_to new_confirmation_path
    assert_equal "Invalid or expired confirmation link.", flash[:alert]
    assert_private_headers
  end

  test "retryable results retain context while terminal results clear it" do
    token = exchange_confirmation_link(@user)

    %i[retryable_busy unavailable].each do |status|
      result = UserAuthenticationLinks::Consume::Result.new(status: status)
      with_singleton_method(UserAuthenticationLinks::Consume, :call, ->(**) { result }) do
        get confirmation_path
      end

      assert_redirected_to confirmation_path
      assert_equal token.id, session.dig(:authentication_link, "token_id")
      assert_private_headers
    end

    terminal = UserAuthenticationLinks::Consume::Result.new(status: :expired)
    with_singleton_method(UserAuthenticationLinks::Consume, :call, ->(**) { terminal }) do
      get confirmation_path
    end

    assert_redirected_to new_confirmation_path
    assert_nil session[:authentication_link]
  end

  test "confirmation succeeds when the optional callback is absent" do
    token = exchange_confirmation_link(@user)
    configuration = RailsSimpleAuth.configuration
    previous_callback = configuration.after_confirmation_callback
    configuration.after_confirmation_callback = nil

    get confirmation_path

    assert_redirected_to new_session_path
    assert @user.reload.confirmed?
    assert token.reload.consumed?
    assert_nil session[:authentication_link]
  ensure
    configuration.after_confirmation_callback = previous_callback if configuration
  end

  test "mail capability drift returns not found" do
    deployment = mail_disabled_deployment
    with_singleton_method(Screenote::Deployment, :current, -> { deployment }) do
      get new_confirmation_path
    end

    assert_response :not_found
  end

  test "confirmation requests are rate limited by client IP" do
    3.times do
      post confirmations_path, params: { email: "missing@example.test" }
      assert_redirected_to new_session_path
    end

    post confirmations_path, params: { email: "missing@example.test" }

    assert_redirected_to new_confirmation_path
    assert_match(/too many confirmation requests/i, flash[:alert])
  end

  test "confirmation requests fail closed when the rate-limit backend is unavailable" do
    unavailable = ->(*, **) { raise IOError, "offline" }

    with_singleton_method(@rate_limit_backend, :increment, unavailable) do
      post confirmations_path, params: { email: @user.email }
    end

    assert_response :service_unavailable
    assert_equal "60", response.headers["Retry-After"]
    assert_equal "no-store", response.headers["Cache-Control"]
    assert_no_enqueued_emails
  end

  private

  def exchange_confirmation_link(user)
    issuance = UserAuthenticationLinks::Issue.call(
      user: user,
      purpose: :email_confirmation,
      enqueue: false
    )
    assert_predicate issuance, :issued?
    token = issuance.token
    presentation = AuthenticationLinks::Issuer.new(
      origin: AuthenticationLinks::Runtime.origin,
      keyring: AuthenticationLinks::Runtime.keyring
    ).re_present(token: token)

    post exchange_authentication_link_path(:email_confirmation), params: { token: presentation.fragment }
    assert_redirected_to confirmation_path
    token
  end

  def assert_private_headers
    assert_includes response.headers.fetch("Cache-Control"), "no-store"
    assert_equal "no-referrer", response.headers["Referrer-Policy"]
    assert_equal "noindex, nofollow", response.headers["X-Robots-Tag"]
  end

  def mail_disabled_deployment
    Screenote::Deployment.new(
      {
        "SCREENOTE_EDITION" => "self_hosted",
        "SCREENOTE_BASE_URL" => "http://screenote.internal"
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
