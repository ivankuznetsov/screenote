# frozen_string_literal: true

# screenote-edition: self_hosted

require "test_helper"

class InvitationAcceptancesControllerTest < ActionDispatch::IntegrationTest
  self.use_transactional_tests = false

  setup do
    @invitation = project_invitations(:pending_invitation)
    @project = @invitation.project
    @issued = nil
    ProjectInvitation.transaction do
      @issued = AuthenticationLinks::Issuer.new(
        origin: AuthenticationLinks::Runtime.origin,
        keyring: AuthenticationLinks::Runtime.keyring
      ).call(
        purpose: :invitation,
        subject: ProjectInvitation.lock.find(@invitation.id),
        expires_at: 7.days.from_now
      )
    end
  end

  teardown do
    AuthenticationToken.delete_all
  end

  test "requires a tokenless exchanged context" do
    get invitation_acceptance_path

    assert_response :unprocessable_content
    assert_select ".invitation-acceptance"
    assert_select "[role=alert]", text: /invalid/i
  end

  test "an exchanged context whose token disappeared is terminal and reveals no invitation" do
    exchange_invitation
    @issued.token.destroy!

    get invitation_acceptance_path

    assert_response :success
    assert_select ".invitation-acceptance", text: /context is invalid/i
    assert_select ".invitation-acceptance__form", count: 0

    get invitation_acceptance_path
    assert_response :unprocessable_content
  end

  test "shows project inviter and invited address after body-only exchange" do
    exchange_invitation
    assert_redirected_to invitation_acceptance_path
    assert_not_includes response.location, @issued.presentation.fragment

    get invitation_acceptance_path

    assert_response :success
    assert_select ".invitation-acceptance", text: /#{Regexp.escape(@project.name)}/
    assert_select ".invitation-acceptance", text: /#{Regexp.escape(@invitation.inviter.email)}/
    assert_select ".invitation-acceptance", text: /#{Regexp.escape(@invitation.email)}/
    assert_select "input[name='acceptance[password]']"
    assert_not_includes response.body, @issued.presentation.fragment
  end

  test "matching session accepts while a different session is told to switch account" do
    invited_user = create_user(@invitation.email)
    sign_in(users(:bob))
    exchange_invitation
    get invitation_acceptance_path
    assert_select "form[action='#{session_path}'] button", text: /Sign out and continue/

    delete session_path
    assert_redirected_to invitation_acceptance_path
    get invitation_acceptance_path
    assert_response :success
    assert_select ".invitation-acceptance", text: /#{Regexp.escape(@invitation.email)}/

    sign_in(invited_user)

    assert_difference "ProjectMembership.count", 1 do
      post invitation_acceptance_path, params: { acceptance: { method: "session" } }
    end

    assert_redirected_to project_path(@project)
    assert @project.member?(invited_user)
    assert @issued.token.reload.consumed?
  end

  test "new invitee creates durable local credentials during acceptance" do
    exchange_invitation

    assert_difference [ "User.count", "ProjectMembership.count", "Session.count" ], 1 do
      post invitation_acceptance_path, params: {
        acceptance: {
          method: "local",
          password: "new-password",
          password_confirmation: "new-password"
        }
      }
    end

    user = User.find_by!(email: @invitation.email)
    assert user.authenticate("new-password")
    assert user.confirmed_at.present?
    assert_redirected_to project_path(@project)
  end

  test "password confirmation mismatch preserves invitation context for retry" do
    exchange_invitation

    assert_no_difference [ "User.count", "ProjectMembership.count", "Session.count" ] do
      post invitation_acceptance_path, params: {
        acceptance: {
          method: "local",
          password: "new-password",
          password_confirmation: "different-password"
        }
      }
    end

    assert_response :unprocessable_content
    assert_select ".invitation-acceptance", text: /#{Regexp.escape(@project.name)}/
    assert_select ".invitation-acceptance", text: /#{Regexp.escape(@invitation.email)}/
    assert_select "[role=alert]", text: /doesn't match/i
    assert_select "input[name='acceptance[password]']"
    assert_select "input[name='acceptance[password_confirmation]']"
    assert @invitation.reload.pending?
    assert @issued.token.reload.outstanding?

    counts_before_retry = [ User.count, ProjectMembership.count, Session.count ]
    post invitation_acceptance_path, params: {
      acceptance: {
        method: "local",
        password: "new-password",
        password_confirmation: "new-password"
      }
    }

    assert_redirected_to project_path(@project)
    assert_equal counts_before_retry.map { |count| count + 1 },
      [ User.count, ProjectMembership.count, Session.count ]
  end


  test "unsupported identity proof keeps a valid invitation context available for retry" do
    exchange_invitation

    post invitation_acceptance_path, params: { acceptance: { method: "unsupported" } }

    assert_response :unprocessable_content
    assert @issued.token.reload.outstanding?
    assert_select ".invitation-acceptance", text: /#{Regexp.escape(@project.name)}/
    assert_select ".invitation-acceptance", text: /#{Regexp.escape(@invitation.email)}/
    assert_select ".invitation-acceptance", text: /context is invalid/i, count: 0

    get invitation_acceptance_path
    assert_response :success
    assert_select ".invitation-acceptance", text: /#{Regexp.escape(@project.name)}/
  end

  test "a token terminalized after exchange is cleared by the acceptance request" do
    exchange_invitation
    @issued.token.transition_to!(:cancelled)

    post invitation_acceptance_path, params: {
      acceptance: {
        method: "local",
        password: "new-password",
        password_confirmation: "new-password"
      }
    }

    assert_response :unprocessable_content
    assert_select "[role=alert]", text: /cancelled/i

    get invitation_acceptance_path
    assert_response :unprocessable_content
    assert_select "[role=alert]", text: /invalid/i
  end

  test "a busy acceptance returns service unavailable and preserves its invitation context" do
    exchange_invitation
    result = acceptance_result(:retryable_busy)

    with_singleton_method_stub(ProjectInvitations::Accept, :call, ->(**) { result }) do
      post invitation_acceptance_path, params: {
        acceptance: {
          method: "local",
          password: "new-password",
          password_confirmation: "new-password"
        }
      }
    end

    assert_response :service_unavailable
    assert_select "[role=alert]", text: /busy/i
    assert_select ".invitation-acceptance", text: /#{Regexp.escape(@project.name)}/
    assert_select ".invitation-acceptance", text: /context is invalid/i, count: 0

    get invitation_acceptance_path
    assert_response :success
    assert_select ".invitation-acceptance", text: /#{Regexp.escape(@project.name)}/
  end

  test "a terminal transition during retry-state recovery clears the context" do
    exchange_invitation
    @issued.token.transition_to!(:cancelled)
    result = acceptance_result(:retryable_busy)

    with_singleton_method_stub(ProjectInvitations::Accept, :call, ->(**) { result }) do
      post invitation_acceptance_path, params: {
        acceptance: {
          method: "local",
          password: "new-password",
          password_confirmation: "new-password"
        }
      }
    end

    assert_response :unprocessable_content
    assert_nil session[:authentication_link]
    assert_select "[role=alert]", text: /cancelled/i
  end

  test "existing invitee signs in through the normal session flow before accepting" do
    invited_user = create_user(@invitation.email)
    exchange_invitation

    get invitation_acceptance_path
    assert_response :success
    assert_select "a[href='#{new_session_path}']", text: /Sign in and continue/
    assert_select "input[name='acceptance[password]']", count: 0

    get new_session_path
    post session_path, params: { email: invited_user.email, password: "password123" }
    assert_redirected_to invitation_acceptance_path

    assert_difference "ProjectMembership.count", 1 do
      post invitation_acceptance_path, params: { acceptance: { method: "session" } }
    end

    assert_redirected_to project_path(@project)
    assert invited_user.sessions.exists?
  end

  test "wrong existing-user password is handled only by the normal login endpoint" do
    user = create_user(@invitation.email)
    exchange_invitation

    assert_no_difference [ "ProjectMembership.count", "Session.count" ] do
      post session_path, params: { email: user.email, password: "wrong-password" }
    end
    assert_response :unprocessable_content
    assert @invitation.reload.pending?
    assert @issued.token.reload.outstanding?

    post session_path, params: { email: user.email, password: "password123" }
    assert_redirected_to invitation_acceptance_path
    assert @invitation.reload.pending?

    post invitation_acceptance_path, params: { acceptance: { method: "session" } }
    assert_redirected_to project_path(@project)
    assert @project.member?(user)
  end

  test "terminalized context renders a stable state and cannot create an account" do
    exchange_invitation
    @issued.token.transition_to!(:cancelled)

    assert_no_difference [ "User.count", "ProjectMembership.count" ] do
      get invitation_acceptance_path
    end

    assert_response :success
    assert_select "[role=alert]", text: /cancelled/i
    post invitation_acceptance_path, params: {
      acceptance: {
        method: "local",
        password: "new-password",
        password_confirmation: "new-password"
      }
    }
    assert_response :unprocessable_content
  end

  private

  def exchange_invitation
    post exchange_authentication_link_path(:invitation),
      params: { token: @issued.presentation.fragment }
  end

  def create_user(email)
    User.create!(email: email, password: "password123", confirmed_at: Time.current)
  end

  def acceptance_result(status, invitation: nil, errors: [])
    ProjectInvitations::Accept::Result.new(
      status: status,
      invitation: invitation,
      user: nil,
      project: invitation&.project,
      errors: errors
    )
  end

  def with_singleton_method_stub(object, method_name, replacement)
    singleton = object.singleton_class
    original = object.method(method_name)
    singleton.define_method(method_name, replacement)
    yield
  ensure
    singleton&.define_method(method_name, original)
  end
end
