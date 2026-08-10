# frozen_string_literal: true

require "test_helper"

class OmniauthCallbacksControllerTest < ActionDispatch::IntegrationTest
  self.use_transactional_tests = false

  setup do
    @email = "oauth-controller-#{SecureRandom.hex(6)}@example.test"
    @previous_test_mode = OmniAuth.config.test_mode
    OmniAuth.config.test_mode = true
  end

  teardown do
    OmniAuth.config.mock_auth[:google_oauth2] = nil
    OmniAuth.config.mock_auth[:github] = nil
    OmniAuth.config.test_mode = @previous_test_mode
    ProjectInvitation.where(email: @email).destroy_all
    AuthenticationToken.where(user_id: User.where(email: @email)).delete_all
    User.where(email: @email).find_each(&:destroy!)
    Current.reset
  end

  test "SaaS callback creates a session only for a provider-verified new identity" do
    mock_google(email: @email, uid: "new-saas-user", verified: true)

    assert_difference [ "User.count", "Session.count" ], 1 do
      get omniauth_callback_path(provider: :google_oauth2)
    end

    assert_redirected_to dashboard_path
    assert_equal "new-saas-user", User.find_by!(email: @email).oauth_uid
  end

  test "unverified and mismatched returning identities create no session or account" do
    mock_google(email: @email, uid: "unverified", verified: false)
    assert_no_difference [ "User.count", "Session.count" ] do
      get omniauth_callback_path(provider: :google_oauth2)
    end
    assert_redirected_to new_session_path

    user = User.create!(
      email: @email,
      password: "password123",
      confirmed_at: Time.current,
      oauth_provider: "google_oauth2",
      oauth_uid: "bound"
    )
    mock_google(email: "different@example.test", uid: "bound", verified: true)
    assert_no_difference "Session.count" do
      get omniauth_callback_path(provider: :google_oauth2)
    end
    assert_redirected_to new_session_path
    assert_empty user.sessions
  end

  test "self-hosted callback never creates an ordinary account" do
    deployment = self_hosted_deployment
    previous = Screenote::Deployment.current
    Screenote::Deployment.instance_variable_set(:@current, deployment)
    mock_google(email: @email, uid: "closed-registration", verified: true)

    assert_no_difference [ "User.count", "Session.count" ] do
      get omniauth_callback_path(provider: :google_oauth2)
    end
    assert_redirected_to new_session_path
  ensure
    Screenote::Deployment.instance_variable_set(:@current, previous)
  end

  test "verified provider resumes invitation from token-id session context" do
    invitation = projects(:alice_project).project_invitations.create!(
      inviter: users(:alice),
      email: @email
    )
    issued = nil
    ProjectInvitation.transaction do
      issued = AuthenticationLinks::Issuer.new(
        origin: AuthenticationLinks::Runtime.origin,
        keyring: AuthenticationLinks::Runtime.keyring
      ).call(
        purpose: :invitation,
        subject: ProjectInvitation.lock.find(invitation.id),
        expires_at: 7.days.from_now
      )
    end
    post exchange_authentication_link_path(:invitation), params: { token: issued.presentation.fragment }
    assert_equal({ "token_id" => issued.token.id, "purpose" => "invitation" }, session[:authentication_link])
    mock_google(email: @email, uid: "invited-provider", verified: true)

    assert_difference [ "User.count", "ProjectMembership.count", "Session.count" ], 1 do
      invitation_oauth_callback
    end

    assert_redirected_to project_path(invitation.project)
    assert_nil session[:authentication_link]
    assert issued.token.reload.consumed?
  end

  test "invitation OAuth form emits explicit local intent while ordinary sign in does not" do
    invitation = projects(:alice_project).project_invitations.create!(
      inviter: users(:alice),
      email: @email
    )
    issued = issue_invitation_link(invitation)
    post exchange_authentication_link_path(:invitation), params: { token: issued.presentation.fragment }

    get invitation_acceptance_path

    assert_response :success
    assert_select "form[action='/auth/google_oauth2'] input[name='origin'][value=?]", invitation_acceptance_path

    get new_session_path

    assert_response :success
    assert_select "form[action='/auth/google_oauth2']" do
      assert_select "input[name='origin'][value=?]", new_session_path
      assert_select "input[name='origin'][value=?]", invitation_acceptance_path, count: 0
    end
  end

  test "invitation OAuth intent without token context cannot create an account or session" do
    mock_google(email: @email, uid: "missing-invitation-context", verified: true)

    assert_no_difference [ "User.count", "Session.count" ] do
      invitation_oauth_callback
    end

    assert_redirected_to invitation_acceptance_path
    assert_equal "This invitation can no longer be accepted.", flash[:alert]
  end

  test "stale invitation context cannot hijack ordinary OAuth sign in" do
    user = User.create!(
      email: @email,
      password: "password123",
      confirmed_at: Time.current,
      oauth_provider: "google_oauth2",
      oauth_uid: "ordinary-sign-in"
    )
    invitation = projects(:alice_project).project_invitations.create!(
      inviter: users(:alice),
      email: @email
    )
    issued = issue_invitation_link(invitation)
    post exchange_authentication_link_path(:invitation), params: { token: issued.presentation.fragment }
    mock_google(email: @email, uid: "ordinary-sign-in", verified: true)

    assert_no_difference "ProjectMembership.count" do
      assert_difference "Session.count", 1 do
        get omniauth_callback_path(provider: :google_oauth2)
      end
    end

    assert_redirected_to dashboard_path
    assert_nil session[:authentication_link]
    assert issued.token.reload.outstanding?
    assert user.sessions.exists?
  end

  test "failure callback returns a generic authentication error" do
    get omniauth_failure_path

    assert_redirected_to new_session_path
    assert_equal "Authentication failed. Please try again.", flash[:alert]
  end

  test "a verified identity is rejected when its provider is disabled" do
    mock_google(email: @email, uid: "disabled-provider", verified: true)

    with_singleton_method(RailsSimpleAuth.configuration, :oauth_provider_enabled?, ->(*) { false }) do
      assert_no_difference [ "User.count", "Session.count" ] do
        get omniauth_callback_path(provider: :google_oauth2)
      end
    end

    assert_redirected_to new_session_path
    assert_equal "OAuth provider not enabled.", flash[:alert]
  end

  test "invitation failures retain only retryable context and explain each outcome" do
    invitation = projects(:alice_project).project_invitations.create!(
      inviter: users(:alice),
      email: @email
    )
    issued = issue_invitation_link(invitation)
    post exchange_authentication_link_path(:invitation), params: { token: issued.presentation.fragment }
    mock_google(email: @email, uid: "invitation-errors", verified: true)

    expected_messages = {
      identity_mismatch: /does not match the invited email/i,
      invalid_identity: /did not verify the invited email/i,
      limit_reached: /reached its member limit/i,
      retryable_busy: /Screenote is busy/i
    }
    expected_messages.each do |status, message|
      result = invitation_result(status)
      with_singleton_method(ProjectInvitations::Accept, :call, ->(**) { result }) do
        invitation_oauth_callback
      end

      assert_redirected_to invitation_acceptance_path
      assert_match message, flash[:alert]
      assert_equal issued.token.id, session.dig(:authentication_link, "token_id")
    end

    terminal = invitation_result(:invalid)
    with_singleton_method(ProjectInvitations::Accept, :call, ->(**) { terminal }) do
      invitation_oauth_callback
    end

    assert_redirected_to invitation_acceptance_path
    assert_equal "This invitation can no longer be accepted.", flash[:alert]
    assert_nil session[:authentication_link]
  end

  test "concurrently removed OAuth user is handled as an inactive session identity" do
    stale_user = User.create!(
      email: @email,
      password: "password123",
      confirmed_at: Time.current
    )
    mock_google(email: @email, uid: "removed-user", verified: true)
    User.where(id: stale_user.id).delete_all

    with_singleton_method(User, :authenticate_verified_oauth, ->(*, **) { stale_user }) do
      assert_no_difference "Session.count" do
        get omniauth_callback_path(provider: :google_oauth2)
      end
    end

    assert_redirected_to new_session_path
    assert_equal "Account access is unavailable.", flash[:alert]
    assert_nil RailsSimpleAuth::Current.user
    assert_nil RailsSimpleAuth::Current.session
  end

  private

  def mock_google(email:, uid:, verified:)
    OmniAuth.config.mock_auth[:google_oauth2] = OmniAuth::AuthHash.new(
      "provider" => "google_oauth2",
      "uid" => uid,
      "info" => { "email" => email, "email_verified" => verified }
    )
  end

  def issue_invitation_link(invitation)
    ProjectInvitation.transaction do
      AuthenticationLinks::Issuer.new(
        origin: AuthenticationLinks::Runtime.origin,
        keyring: AuthenticationLinks::Runtime.keyring
      ).call(
        purpose: :invitation,
        subject: ProjectInvitation.lock.find(invitation.id),
        expires_at: 7.days.from_now
      )
    end
  end

  def invitation_oauth_callback
    get omniauth_callback_path(provider: :google_oauth2),
      env: { "omniauth.origin" => invitation_acceptance_path }
  end

  def invitation_result(status)
    ProjectInvitations::Accept::Result.new(
      status: status,
      invitation: nil,
      user: nil,
      project: nil,
      errors: {}
    )
  end

  def with_singleton_method(object, name, implementation)
    original = object.method(name)
    object.define_singleton_method(name, implementation)
    yield
  ensure
    object.define_singleton_method(name, original) if original
  end

  def self_hosted_deployment
    Screenote::Deployment.new(
      {
        "SCREENOTE_EDITION" => "self_hosted",
        "SCREENOTE_BASE_URL" => "http://screenote.internal",
        "SCREENOTE_GOOGLE_OAUTH_ENABLED" => "1",
        "GOOGLE_CLIENT_ID" => "google-client",
        "GOOGLE_CLIENT_SECRET" => "google-secret"
      },
      production: false
    )
  end
end
