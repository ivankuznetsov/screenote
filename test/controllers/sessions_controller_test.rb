# frozen_string_literal: true

require "test_helper"

class SessionsControllerTest < ActionDispatch::IntegrationTest
  self.use_transactional_tests = false

  setup do
    @rate_limit_backend = ActiveSupport::Cache::MemoryStore.new
    ActionController::Base.cache_store = @rate_limit_backend
    @email_prefix = "session-controller-#{SecureRandom.hex(6)}"
    @user = User.create!(
      email: "#{@email_prefix}-confirmed@example.test",
      password: "password123",
      confirmed_at: Time.current
    )
  end

  teardown do
    ProjectInvitation.where("email LIKE ?", "#{@email_prefix}%").find_each(&:destroy!)
    User.where("email LIKE ?", "#{@email_prefix}%").find_each(&:destroy!)
    Current.reset
  end

  test "new stores a same-origin referrer for guests and redirects permanent users" do
    get new_session_path,
      headers: { "HTTP_REFERER" => "http://www.example.com/projects/42?viewport=mobile" }

    assert_response :success
    assert_equal "/projects/42?viewport=mobile", session[:return_to]

    sign_in(@user)
    get new_session_path
    assert_redirected_to dashboard_path
  end

  test "unconfirmed accounts receive a specific error while invalid credentials remain generic" do
    unconfirmed = User.create!(
      email: "#{@email_prefix}-unconfirmed@example.test",
      password: "password123"
    )

    assert_no_difference "Session.count" do
      post session_path, params: { email: unconfirmed.email, password: "password123" }
    end
    assert_response :unprocessable_content
    assert_select ".auth-card__error", text: /confirm your email/i
    assert_select "input[name='email'][value='#{unconfirmed.email}']"

    assert_no_difference "Session.count" do
      post session_path, params: { email: @user.email, password: "wrong-password" }
      assert_response :unprocessable_content

      post session_path, params: { email: "missing@example.test", password: "password123" }
      assert_response :unprocessable_content
    end
    assert_select ".auth-card__error", text: /Invalid email or password/
  end

  test "active suspended and missing identities all use timing-safe password work" do
    suspended_user = User.create!(
      email: "#{@email_prefix}-suspended@example.test",
      password: "password123",
      confirmed_at: Time.current,
      access_status: :suspended
    )
    calls = []
    authenticate_by = User.method(:authenticate_by)
    instrumented_authentication = lambda do |attributes|
      calls << attributes
      authenticate_by.call(attributes)
    end

    with_singleton_method(User, :authenticate_by, instrumented_authentication) do
      post session_path, params: { email: @user.email.upcase, password: "wrong-password" }
      assert_response :unprocessable_content

      post session_path, params: { email: suspended_user.email, password: "password123" }
      assert_response :unprocessable_content

      post session_path, params: { email: " MISSING@EXAMPLE.TEST ", password: "attempted-password" }
      assert_response :unprocessable_content
    end

    assert_equal(
      [
        { email: @user.email, password: "wrong-password" },
        { email: suspended_user.email, password: "password123" },
        { email: "missing@example.test", password: "attempted-password" }
      ],
      calls
    )
  end

  test "signing in twice as the same account retains the current session" do
    sign_in(@user)
    session_record = @user.sessions.last!

    assert_no_difference "Session.count" do
      post session_path, params: { email: @user.email, password: "password123" }
    end

    assert_redirected_to dashboard_path
    assert_equal [ session_record.id ], @user.sessions.reload.ids
  end

  test "invitation context controls both post-sign-in and sign-out destinations" do
    invitation = projects(:alice_project).project_invitations.create!(
      inviter: users(:alice),
      email: @user.email
    )
    issued = issue_invitation_link(invitation)
    post exchange_authentication_link_path(:invitation), params: { token: issued.presentation.fragment }
    assert_redirected_to invitation_acceptance_path

    post session_path, params: { email: @user.email, password: "password123" }
    assert_redirected_to invitation_acceptance_path
    browser_session_id = @user.sessions.last!.id

    delete session_path

    assert_redirected_to invitation_acceptance_path
    assert_not Session.exists?(browser_session_id)
    assert_equal issued.token.id, session.dig(:authentication_link, "token_id")
  end

  test "a cookie for a missing session is cleared before authentication" do
    sign_in(@user)
    session_record = @user.sessions.last!
    Session.where(id: session_record.id).delete_all

    get dashboard_path

    assert_redirected_to new_session_path
    assert_predicate cookies[:session_token], :blank?
    assert_nil RailsSimpleAuth::Current.user
    assert_nil RailsSimpleAuth::Current.session
  end

  test "login attempts are rate limited by client IP" do
    5.times do
      post session_path, params: { email: @user.email, password: "wrong-password" }
      assert_response :unprocessable_content
    end

    post session_path, params: { email: @user.email, password: "wrong-password" }

    assert_redirected_to new_session_path
    assert_match(/too many login attempts/i, flash[:alert])
  end

  test "login attempts fail closed when the rate-limit backend is unavailable" do
    unavailable = ->(*, **) { raise IOError, "offline" }

    with_singleton_method(@rate_limit_backend, :increment, unavailable) do
      assert_no_difference "Session.count" do
        post session_path, params: { email: @user.email, password: "password123" }
      end
    end

    assert_response :service_unavailable
    assert_equal "60", response.headers["Retry-After"]
    assert_equal "no-store", response.headers["Cache-Control"]
  end

  private

  def issue_invitation_link(invitation)
    ProjectInvitation.transaction do
      AuthenticationLinks::Issuer.new(
        origin: AuthenticationLinks::Runtime.origin,
        keyring: AuthenticationLinks::Runtime.keyring
      ).call(
        purpose: :invitation,
        subject: ProjectInvitation.lock.find(invitation.id),
        expires_at: 15.minutes.from_now
      )
    end
  end

  def with_singleton_method(object, name, implementation)
    original = object.method(name)
    object.define_singleton_method(name, implementation)
    yield
  ensure
    object.define_singleton_method(name, original) if original
  end
end
