# frozen_string_literal: true

require "test_helper"

class PasswordsControllerTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper
  self.use_transactional_tests = false

  setup do
    @rate_limit_backend = ActiveSupport::Cache::MemoryStore.new
    ActionController::Base.cache_store = @rate_limit_backend
    @user = User.create!(
      email: "password-controller-#{SecureRandom.hex(6)}@example.test",
      password: "password123",
      confirmed_at: Time.current
    )
    clear_enqueued_jobs
  end

  teardown do
    @user.destroy! if @user&.persisted?
    clear_enqueued_jobs
    Current.reset
  end

  test "new renders and create remains enumeration-safe" do
    get new_password_path
    assert_response :success

    assert_no_difference "AuthenticationToken.count" do
      post passwords_path, params: { email: "missing-#{SecureRandom.hex(4)}@example.test" }
    end
    assert_redirected_to new_session_path

    assert_difference -> { @user.authentication_tokens.password_reset.outstanding.count }, 1 do
      assert_enqueued_emails 1 do
        post passwords_path, params: { email: @user.email.upcase }
      end
    end
    assert_redirected_to new_session_path
  end

  test "edit clears context when a previously exchanged token becomes invalid" do
    token = exchange_password_link(@user)
    token.transition_to!(:cancelled)

    get edit_password_path

    assert_redirected_to new_password_path
    assert_nil session[:authentication_link]
    assert_private_headers
  end

  test "update without context redirects to a fresh request" do
    patch password_path, params: {
      user: { password: "replacement-password", password_confirmation: "replacement-password" }
    }

    assert_redirected_to new_password_path
    assert_equal "Invalid or expired password reset link.", flash[:alert]
    assert_private_headers
  end

  test "validation, retryable, and terminal consume results preserve the correct context" do
    token = exchange_password_link(@user)
    attributes = {
      user: { password: "replacement-password", password_confirmation: "replacement-password" }
    }
    validation = UserAuthenticationLinks::Consume::Result.new(
      status: :validation_failed,
      errors: { password: [ "is invalid" ] }
    )

    with_singleton_method(UserAuthenticationLinks::Consume, :call, ->(**) { validation }) do
      patch password_path, params: attributes
    end
    assert_response :unprocessable_content
    assert_select "[role='alert']", text: "is invalid"
    assert_equal token.id, session.dig(:authentication_link, "token_id")

    %i[retryable_busy unavailable].each do |status|
      result = UserAuthenticationLinks::Consume::Result.new(status: status)
      with_singleton_method(UserAuthenticationLinks::Consume, :call, ->(**) { result }) do
        patch password_path, params: attributes
      end

      assert_redirected_to edit_password_path
      assert_equal token.id, session.dig(:authentication_link, "token_id")
    end

    terminal = UserAuthenticationLinks::Consume::Result.new(status: :expired)
    with_singleton_method(UserAuthenticationLinks::Consume, :call, ->(**) { terminal }) do
      patch password_path, params: attributes
    end

    assert_redirected_to new_password_path
    assert_nil session[:authentication_link]
  end

  test "resetting the signed-in account clears its now-revoked browser session" do
    token = exchange_password_link(@user)
    sign_in(@user)
    browser_session_id = @user.sessions.order(:id).last!.id

    patch password_path, params: {
      user: { password: "replacement-password", password_confirmation: "replacement-password" }
    }

    assert_redirected_to new_session_path
    assert token.reload.consumed?
    assert_not Session.exists?(browser_session_id)
    assert_empty @user.reload.sessions
    assert_predicate cookies[:session_token], :blank?
  end

  test "mail capability drift returns not found" do
    deployment = mail_disabled_deployment
    with_singleton_method(Screenote::Deployment, :current, -> { deployment }) do
      get new_password_path
    end

    assert_response :not_found
  end

  test "password reset requests are rate limited by client IP" do
    3.times do
      post passwords_path, params: { email: "missing@example.test" }
      assert_redirected_to new_session_path
    end

    post passwords_path, params: { email: "missing@example.test" }

    assert_redirected_to new_password_path
    assert_match(/too many password reset requests/i, flash[:alert])
  end

  test "password reset requests fail closed when the rate-limit backend is unavailable" do
    unavailable = ->(*, **) { raise IOError, "offline" }

    with_singleton_method(@rate_limit_backend, :increment, unavailable) do
      post passwords_path, params: { email: @user.email }
    end

    assert_response :service_unavailable
    assert_equal "60", response.headers["Retry-After"]
    assert_equal "no-store", response.headers["Cache-Control"]
    assert_no_enqueued_emails
  end

  private

  def exchange_password_link(user)
    issuance = UserAuthenticationLinks::Issue.call(user: user, purpose: :password_reset, enqueue: false)
    assert_predicate issuance, :issued?
    token = issuance.token
    presentation = AuthenticationLinks::Issuer.new(
      origin: AuthenticationLinks::Runtime.origin,
      keyring: AuthenticationLinks::Runtime.keyring
    ).re_present(token: token)

    post exchange_authentication_link_path(:password_reset), params: { token: presentation.fragment }
    assert_redirected_to edit_password_path
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
