# frozen_string_literal: true

require "test_helper"

class AppAuthenticationControllerTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper
  self.use_transactional_tests = false

  setup do
    @email_prefix = "app-auth-#{SecureRandom.hex(6)}"
    clear_enqueued_jobs
  end

  teardown do
    User.where("email LIKE ?", "#{@email_prefix}%").find_each(&:destroy!)
    clear_enqueued_jobs
    Current.reset
  end

  test "password sign in and session loading both reject suspended users" do
    user = create_user("active")
    post session_path, params: { email: user.email, password: "password123" }
    assert_redirected_to dashboard_path
    assert user.sessions.exists?

    user.update!(access_status: :suspended)
    get dashboard_path
    assert_redirected_to new_session_path

    delete session_path
    post session_path, params: { email: user.email, password: "password123" }
    assert_response :unprocessable_content
    assert_select ".auth-card__error", text: /Invalid email or password/
  end

  test "SaaS registration creates an unconfirmed account through the app-owned flow" do
    email = "#{@email_prefix}-registration@example.test"

    assert_difference [ "User.count", "AuthenticationToken.count" ], 1 do
      assert_no_difference "Session.count" do
        post sign_up_path, params: {
          user: {
            email: email.upcase,
            password: "password123",
            password_confirmation: "password123"
          }
        }
      end
    end

    assert_redirected_to new_session_path
    user = User.find_by!(email: email)
    assert user.unconfirmed?
    assert user.authentication_tokens.email_confirmation.outstanding.exists?
    assert_equal 1, enqueued_jobs.count { |job| job[:job] == ActionMailer::MailDeliveryJob }
  end

  test "password reset is tokenless after exchange and consumes exactly once" do
    user = create_user("password")
    user.sessions.create!(ip_address: "127.0.0.1", user_agent: "Test")

    assert_enqueued_emails 1 do
      post passwords_path, params: { email: user.email }
    end
    token = user.authentication_tokens.password_reset.outstanding.order(:id).last!
    presentation = represent(token)

    post exchange_authentication_link_path(:password_reset), params: { token: presentation.fragment }
    assert_redirected_to edit_password_path
    get edit_password_path
    assert_response :success
    assert_not_includes response.body, presentation.fragment

    patch password_path, params: {
      user: { password: "replacement-password", password_confirmation: "replacement-password" }
    }
    assert_redirected_to new_session_path
    assert token.reload.consumed?
    assert user.reload.authenticate("replacement-password")
    assert_empty user.sessions

    get edit_password_path
    assert_redirected_to new_password_path
  end

  test "magic link consumes before creating the browser session" do
    user = create_user("magic")
    post request_magic_link_path, params: { email: user.email }
    token = user.authentication_tokens.magic_link.outstanding.last!
    presentation = represent(token)

    post exchange_authentication_link_path(:magic_link), params: { token: presentation.fragment }
    assert_redirected_to magic_link_path
    assert_difference "Session.count", 1 do
      get magic_link_path
    end

    assert_redirected_to dashboard_path
    assert token.reload.consumed?
    assert_nil session[:authentication_link]
  end

  test "email confirmation consumes once and does not create a session" do
    user = create_user("confirmation", confirmed: false)
    post confirmations_path, params: { email: user.email }
    token = user.authentication_tokens.email_confirmation.outstanding.last!
    presentation = represent(token)

    post exchange_authentication_link_path(:email_confirmation), params: { token: presentation.fragment }
    assert_redirected_to confirmation_path
    assert_no_difference "Session.count" do
      get confirmation_path
    end

    assert_redirected_to new_session_path
    assert user.reload.confirmed?
    assert token.reload.consumed?
  end

  test "authentication-link context accepts only exact token and purpose shapes" do
    controller, request = bare_sessions_controller

    [ nil, "invalid", [], { "token_id" => "1", "purpose" => "magic_link" },
      { "token_id" => -1, "purpose" => "magic_link" },
      { "token_id" => 1, "purpose" => "unknown" } ].each do |value|
      request.session[:authentication_link] = value
      assert_nil controller.send(:authentication_link_context)
    end

    request.session[:authentication_link] = { token_id: 7, purpose: "magic_link" }
    assert_equal(
      { token_id: 7, purpose: "magic_link" },
      controller.send(:authentication_link_context, :magic_link)
    )
    assert_nil controller.send(:authentication_link_context, :password_reset)

    controller.send(:clear_authentication_link_context)
    assert_nil request.session[:authentication_link]
  end

  test "authentication-link context storage rejects invalid values" do
    controller, request = bare_sessions_controller

    assert_raises(ArgumentError) do
      controller.send(:store_authentication_link_context, token_id: "1", purpose: :magic_link)
    end
    assert_raises(ArgumentError) do
      controller.send(:store_authentication_link_context, token_id: 1, purpose: :unknown)
    end

    controller.send(:store_authentication_link_context, token_id: 1, purpose: :magic_link)
    assert_equal(
      { "token_id" => 1, "purpose" => "magic_link" },
      request.session[:authentication_link]
    )
  end

  test "session issuance rejects non-persisted, inactive, and concurrently deleted users" do
    controller, = bare_sessions_controller
    inactive = create_user("inactive")
    inactive.update!(access_status: :suspended)
    stale = create_user("stale")
    User.where(id: stale.id).delete_all

    [ nil, User.new, inactive, stale ].each do |user|
      assert_raises(ScreenoteSessionManagement::InactiveUser) do
        controller.send(:create_session_for, user)
      end
    end
  end

  test "current-session ownership requires matching active persisted state" do
    controller, = bare_sessions_controller
    user = create_user("ownership")
    session_record = user.sessions.create!(ip_address: "127.0.0.1", user_agent: "Test")

    assert_not controller.send(:current_session_belongs_to?, nil)
    assert_not controller.send(:current_session_belongs_to?, User.new)
    assert_not controller.send(:current_session_belongs_to?, user)

    RailsSimpleAuth::Current.user = user
    assert_not controller.send(:current_session_belongs_to?, user)

    RailsSimpleAuth::Current.session = session_record
    assert controller.send(:current_session_belongs_to?, user)

    session_record.delete
    assert_not controller.send(:current_session_belongs_to?, user)
  end

  test "inactive-session handler clears identity and redirects safely" do
    controller, = bare_sessions_controller
    user = create_user("handler")
    RailsSimpleAuth::Current.user = user
    RailsSimpleAuth::Current.session = user.sessions.create!(ip_address: "127.0.0.1", user_agent: "Test")

    controller.send(:handle_inactive_session_user)

    assert_equal 302, controller.response.status
    assert_equal "http://www.example.com#{new_session_path}", controller.response.location
    assert_nil RailsSimpleAuth::Current.user
    assert_nil RailsSimpleAuth::Current.session
  end

  private

  def create_user(suffix, confirmed: true)
    User.create!(
      email: "#{@email_prefix}-#{suffix}@example.test",
      password: "password123",
      confirmed_at: (Time.current if confirmed)
    )
  end

  def represent(token)
    AuthenticationLinks::Issuer.new(
      origin: AuthenticationLinks::Runtime.origin,
      keyring: AuthenticationLinks::Runtime.keyring
    ).re_present(token: token)
  end

  def bare_sessions_controller
    controller = SessionsController.new
    request = ActionController::TestRequest.create(controller.class)
    request.host = "www.example.com"
    controller.set_request!(request)
    controller.set_response!(ActionDispatch::TestResponse.new)
    [ controller, request ]
  end
end
