# frozen_string_literal: true

require "test_helper"

class ProjectInvitationsControllerTest < ActionDispatch::IntegrationTest
  self.use_transactional_tests = false

  setup do
    @owner = users(:alice)
    @member = users(:bob)
    @project = projects(:alice_project)
    @invitation = project_invitations(:pending_invitation)
  end

  teardown do
    AuthenticationToken.delete_all
  end

  # Authorization

  test "requires authentication" do
    post project_invitations_path(@project), params: { project_invitation: { email: "x@example.com" } }
    assert_redirected_to new_session_path
  end

  test "requires owner role to create" do
    sign_in(@member)
    post project_invitations_path(@project), params: { project_invitation: { email: "x@example.com" } }
    assert_redirected_to projects_path
  end

  test "requires owner role to destroy" do
    sign_in(@member)
    delete project_invitation_path(@project, @invitation)
    assert_redirected_to projects_path
  end

  # Create

  test "owner can send invitation" do
    sign_in(@owner)
    assert_difference [ "ProjectInvitation.count", "AuthenticationToken.count" ], 1 do
      post project_invitations_path(@project), params: { project_invitation: { email: "invitee@example.com" } }
    end
    assert_redirected_to project_memberships_path(@project)
  end

  test "mail-disabled installations explain how to share the private link" do
    sign_in(@owner)
    result = issue_result(:issued, invitation: @invitation, delivery_status: :not_requested)

    with_current_deployment(mail_disabled_deployment) do
      with_singleton_method_stub(ProjectInvitations::Issue, :call, ->(**) { result }) do
        post project_invitations_path(@project),
          params: { project_invitation: { email: @invitation.email } }
      end
    end

    assert_redirected_to project_memberships_path(@project)
    assert_equal "Invitation created. Copy its private link below and share it only with the invitee.", flash[:notice]
  end

  test "sends invitation email" do
    sign_in(@owner)
    assert_enqueued_emails 1 do
      post project_invitations_path(@project), params: { project_invitation: { email: "invitee@example.com" } }
    end
    assert_redirected_to project_memberships_path(@project)
    assert_equal "Invitation sent to invitee@example.com.", flash[:notice]
  end

  test "rejects invalid email" do
    sign_in(@owner)
    assert_no_difference "ProjectInvitation.count" do
      post project_invitations_path(@project), params: { project_invitation: { email: "" } }
    end
    assert_redirected_to project_memberships_path(@project)
    follow_redirect!
    assert_select ".flash--alert"
  end

  test "rejects duplicate invitation" do
    sign_in(@owner)
    assert_no_difference "ProjectInvitation.count" do
      post project_invitations_path(@project), params: { project_invitation: { email: @invitation.email } }
    end
    assert_redirected_to project_memberships_path(@project)
    assert_equal 1, @invitation.authentication_tokens.count
    assert_equal "Invitation link reissued. Copy the new private link below.", flash[:notice]
  end

  test "an already-pending service result keeps the existing private link" do
    sign_in(@owner)
    result = issue_result(:already_pending, invitation: @invitation)

    with_singleton_method_stub(ProjectInvitations::Issue, :call, ->(**) { result }) do
      post project_invitations_path(@project),
        params: { project_invitation: { email: @invitation.email } }
    end

    assert_redirected_to project_memberships_path(@project)
    assert_equal "That invitation is already pending. Its private link is available below.", flash[:notice]
  end

  test "validation errors from invitation issuance are shown to the owner" do
    sign_in(@owner)
    result = issue_result(:invalid, errors: [ "Email has already been reserved" ])

    with_singleton_method_stub(ProjectInvitations::Issue, :call, ->(**) { result }) do
      post project_invitations_path(@project),
        params: { project_invitation: { email: "reserved@example.test" } }
    end

    assert_redirected_to project_memberships_path(@project)
    assert_equal "Email has already been reserved", flash[:alert]
  end

  test "mail enqueue failure directs the owner to the committed private link" do
    sign_in(@owner)
    result = issue_result(:issued, invitation: @invitation, delivery_status: :failed)

    with_singleton_method_stub(ProjectInvitations::Issue, :call, ->(**) { result }) do
      post project_invitations_path(@project),
        params: { project_invitation: { email: @invitation.email } }
    end

    assert_redirected_to project_memberships_path(@project)
    assert_equal "Invitation created, but email could not be queued. Copy its private link below.", flash[:notice]
  end

  test "issuer and authorization races fail closed" do
    sign_in(@owner)
    {
      inactive_issuer: [ new_session_path, "Your account is not active." ],
      forbidden: [ projects_path, "Only active project owners can invite collaborators." ],
      retryable_busy: [ project_memberships_path(@project), "The invitation is busy. Please try again." ]
    }.each do |status, (destination, message)|
      result = issue_result(status)

      with_singleton_method_stub(ProjectInvitations::Issue, :call, ->(**) { result }) do
        post project_invitations_path(@project),
          params: { project_invitation: { email: "race@example.test" } }
      end

      assert_redirected_to destination
      assert_equal message, flash[:alert]
    end
  end

  test "a project removed during issuance returns not found" do
    sign_in(@owner)
    result = issue_result(:not_found)

    with_singleton_method_stub(ProjectInvitations::Issue, :call, ->(**) { result }) do
      post project_invitations_path(@project),
        params: { project_invitation: { email: "race@example.test" } }
    end

    assert_response :not_found
  end

  test "an unexpected issuance result fails closed" do
    sign_in(@owner)
    result = issue_result(:unexpected)

    with_singleton_method_stub(ProjectInvitations::Issue, :call, ->(**) { result }) do
      post project_invitations_path(@project),
        params: { project_invitation: { email: "unexpected@example.test" } }
    end

    assert_redirected_to project_memberships_path(@project)
    assert_equal "The invitation could not be created.", flash[:alert]
  end

  test "owner cannot invite themselves" do
    sign_in(@owner)
    assert_no_difference "ProjectInvitation.count" do
      post project_invitations_path(@project), params: { project_invitation: { email: @owner.email } }
    end
    assert_redirected_to project_memberships_path(@project)
  end

  # Destroy

  test "owner can cancel pending invitation" do
    sign_in(@owner)
    assert_no_difference "ProjectInvitation.count" do
      delete project_invitation_path(@project, @invitation)
    end
    assert_redirected_to project_memberships_path(@project)
    assert @invitation.reload.cancelled?
  end

  test "cancel of already-accepted invitation shows alert" do
    sign_in(@owner)
    @invitation.update!(status: :accepted)
    assert_no_difference "ProjectInvitation.count" do
      delete project_invitation_path(@project, @invitation)
    end
    assert_redirected_to project_memberships_path(@project)
    follow_redirect!
    assert_select ".flash--alert"
  end

  test "cancel of an already-cancelled invitation is idempotent" do
    sign_in(@owner)
    @invitation.update!(status: :cancelled)

    delete project_invitation_path(@project, @invitation)

    assert_redirected_to project_memberships_path(@project)
    assert_equal "Invitation was already cancelled.", flash[:notice]
  end

  test "cancellation authorization and lock races fail closed" do
    sign_in(@owner)
    {
      forbidden: [ projects_path, "Only active project owners can cancel invitations." ],
      retryable_busy: [ project_memberships_path(@project), "The invitation is busy. Please try again." ]
    }.each do |status, (destination, message)|
      result = cancel_result(status)

      with_singleton_method_stub(ProjectInvitations::Cancel, :call, ->(**) { result }) do
        delete project_invitation_path(@project, @invitation)
      end

      assert_redirected_to destination
      assert_equal message, flash[:alert]
    end
  end

  test "a missing invitation returns not found during cancellation" do
    sign_in(@owner)

    delete project_invitation_path(@project, 0)

    assert_response :not_found
  end

  test "an unexpected cancellation result fails closed" do
    sign_in(@owner)
    result = cancel_result(:unexpected)

    with_singleton_method_stub(ProjectInvitations::Cancel, :call, ->(**) { result }) do
      delete project_invitation_path(@project, @invitation)
    end

    assert_redirected_to project_memberships_path(@project)
    assert_equal "The invitation could not be cancelled.", flash[:alert]
  end

  # Plan limit enforcement

  test "free owner at member limit is redirected from create" do
    free_owner = users(:bob)
    free_project = projects(:bob_project)

    # Add a member to reach the limit
    free_project.project_memberships.create!(user: users(:unconfirmed), role: :member)

    sign_in(free_owner)
    assert_no_difference "ProjectInvitation.count" do
      post project_invitations_path(free_project), params: { project_invitation: { email: "blocked@example.com" } }
    end
    assert_redirected_to subscription_path
  end

  test "pro owner can invite beyond free limit" do
    sign_in(@owner) # alice is pro
    assert_difference "ProjectInvitation.count", 1 do
      post project_invitations_path(@project), params: { project_invitation: { email: "another-invitee@example.com" } }
    end
    assert_redirected_to project_memberships_path(@project)
  end


  private

  def issue_result(status, invitation: nil, delivery_status: :not_requested, errors: [])
    ProjectInvitations::Issue::Result.new(
      status: status,
      invitation: invitation,
      token: nil,
      presentation: nil,
      delivery_status: delivery_status,
      errors: errors
    )
  end

  def cancel_result(status)
    ProjectInvitations::Cancel::Result.new(status: status, invitation: @invitation)
  end

  def mail_disabled_deployment
    @mail_disabled_deployment ||= Screenote::Deployment.new(
      {
        "SCREENOTE_EDITION" => "self_hosted",
        "SCREENOTE_BASE_URL" => "http://screenote.internal"
      },
      production: false
    )
  end

  def with_current_deployment(deployment)
    previous = Screenote::Deployment.current
    Screenote::Deployment.instance_variable_set(:@current, deployment)
    yield
  ensure
    Screenote::Deployment.instance_variable_set(:@current, previous)
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
