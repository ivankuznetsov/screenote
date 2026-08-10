# frozen_string_literal: true

require "test_helper"

class MagicLinksControllerTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper
  self.use_transactional_tests = false

  setup do
    @rate_limit_backend = ActiveSupport::Cache::MemoryStore.new
    ActionController::Base.cache_store = @rate_limit_backend
    @email_prefix = "magic-controller-#{SecureRandom.hex(6)}"
    @user = User.create!(
      email: "#{@email_prefix}-confirmed@example.test",
      password: "password123",
      confirmed_at: Time.current
    )
    clear_enqueued_jobs
  end

  teardown do
    User.where("email LIKE ?", "#{@email_prefix}%").find_each(&:destroy!)
    clear_enqueued_jobs
    Current.reset
  end

  test "new stores a same-origin referrer for a guest" do
    get magic_link_form_path,
      headers: { "HTTP_REFERER" => "http://www.example.com/projects/42?viewport=mobile" }

    assert_response :success
    assert_equal "/projects/42?viewport=mobile", session[:return_to]
  end

  test "new redirects an already signed-in permanent user" do
    sign_in(@user)

    get magic_link_form_path

    assert_redirected_to dashboard_path
  end

  test "create is enumeration-safe for missing users and issues for an existing user" do
    assert_no_difference "AuthenticationToken.count" do
      post request_magic_link_path, params: { email: "missing-#{SecureRandom.hex(4)}@example.test" }
    end
    assert_redirected_to new_session_path

    assert_difference -> { @user.authentication_tokens.magic_link.outstanding.count }, 1 do
      assert_enqueued_emails 1 do
        post request_magic_link_path, params: { email: @user.email.upcase }
      end
    end
    assert_redirected_to new_session_path
  end

  test "show rejects missing context with private response headers" do
    get magic_link_path

    assert_redirected_to new_session_path
    assert_equal "Invalid or expired magic link.", flash[:alert]
    assert_private_headers
  end

  test "retryable results retain context while terminal results clear it" do
    token = exchange_magic_link(@user)

    %i[retryable_busy unavailable].each do |status|
      result = UserAuthenticationLinks::Consume::Result.new(status: status)
      with_singleton_method(UserAuthenticationLinks::Consume, :call, ->(**) { result }) do
        get magic_link_path
      end

      assert_redirected_to magic_link_path
      assert_equal token.id, session.dig(:authentication_link, "token_id")
      assert_private_headers
    end

    terminal = UserAuthenticationLinks::Consume::Result.new(status: :expired)
    with_singleton_method(UserAuthenticationLinks::Consume, :call, ->(**) { terminal }) do
      get magic_link_path
    end

    assert_redirected_to new_session_path
    assert_nil session[:authentication_link]
  end

  test "first magic-link confirmation enqueues a welcome message after session creation" do
    user = User.create!(
      email: "#{@email_prefix}-unconfirmed@example.test",
      password: "password123"
    )
    token = exchange_magic_link(user)

    assert_difference "Session.count", 1 do
      assert_enqueued_emails 1 do
        get magic_link_path
      end
    end

    assert_redirected_to dashboard_path
    assert user.reload.confirmed?
    assert token.reload.consumed?
    assert_nil session[:authentication_link]
  end

  test "rate-limit identity canonicalizes email without exposing it" do
    canonical = MagicLinksController.rate_limit_identity("  USER@Example.Test ")

    assert_equal canonical, MagicLinksController.rate_limit_identity("user@example.test")
    assert_equal 64, canonical.length
    assert_not_includes canonical, "user"
  end

  test "mail capability drift returns not found" do
    deployment = mail_disabled_deployment
    with_singleton_method(Screenote::Deployment, :current, -> { deployment }) do
      get magic_link_form_path
    end

    assert_response :not_found
  end

  test "magic-link requests are rate limited by canonical email" do
    3.times do
      post request_magic_link_path, params: { email: " Missing@Example.Test " }
      assert_redirected_to new_session_path
    end

    post request_magic_link_path, params: { email: "missing@example.test" }

    assert_redirected_to magic_link_form_path
    assert_match(/too many magic link requests/i, flash[:alert])
  end

  test "magic-link requests fail closed when the rate-limit backend is unavailable" do
    unavailable = ->(*, **) { raise IOError, "offline" }

    with_singleton_method(@rate_limit_backend, :increment, unavailable) do
      post request_magic_link_path, params: { email: @user.email }
    end

    assert_response :service_unavailable
    assert_equal "60", response.headers["Retry-After"]
    assert_equal "no-store", response.headers["Cache-Control"]
    assert_no_enqueued_emails
  end

  private

  def exchange_magic_link(user)
    issuance = UserAuthenticationLinks::Issue.call(user: user, purpose: :magic_link, enqueue: false)
    assert_predicate issuance, :issued?
    token = issuance.token
    presentation = AuthenticationLinks::Issuer.new(
      origin: AuthenticationLinks::Runtime.origin,
      keyring: AuthenticationLinks::Runtime.keyring
    ).re_present(token: token)

    post exchange_authentication_link_path(:magic_link), params: { token: presentation.fragment }
    assert_redirected_to magic_link_path
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
