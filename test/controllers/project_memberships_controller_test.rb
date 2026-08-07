# frozen_string_literal: true

# screenote-edition: self_hosted

require "test_helper"

class ProjectMembershipsControllerTest < ActionDispatch::IntegrationTest
  self.use_transactional_tests = false

  setup do
    @owner = users(:alice)
    @member = users(:bob)
    @project = projects(:alice_project)
    @member_membership = project_memberships(:bob_member_of_alice_project)
  end

  teardown do
    AuthenticationToken.delete_all
  end

  # Authentication

  test "requires authentication" do
    get project_memberships_path(@project)
    assert_redirected_to new_session_path
  end

  # Index

  test "owner can view members" do
    sign_in(@owner)
    get project_memberships_path(@project)
    assert_response :success
    assert_select ".project-members__email", @owner.email
    assert_select ".project-members__email", @member.email
  end

  test "member can view members" do
    sign_in(@member)
    get project_memberships_path(@project)
    assert_response :success
    assert_select ".project-members__email", @owner.email
  end

  test "member does not see invite form" do
    sign_in(@member)
    get project_memberships_path(@project)
    assert_select ".project-members__invite", count: 0
  end

  test "owner sees invite form" do
    sign_in(@owner)
    get project_memberships_path(@project)
    assert_select ".project-members__invite"
    assert_select "label[for='project_invitation_email']", text: "Collaborator email"
  end

  test "owner sees a private fragment link and manual code for a pending invitation" do
    invitation = project_invitations(:pending_invitation)
    issued = issue_invitation_link(invitation)

    sign_in(@owner)
    get project_memberships_path(@project)

    assert_response :success
    assert_includes response.headers.fetch("Cache-Control"), "no-store"
    assert_equal "no-referrer", response.headers["Referrer-Policy"]
    assert_equal "noindex, nofollow", response.headers["X-Robots-Tag"]
    assert_select "[data-testid='invitation-credential'][data-turbo-temporary]" do
      assert_select "input[value=?]", issued.presentation.url
      assert_select "input[value=?]", issued.presentation.manual_code
      assert_select ".form__hint", text: /Private credential/
    end
  end

  test "owner can reissue an invitation whose stored credential cannot be presented" do
    invitation = project_invitations(:pending_invitation)
    issued = issue_invitation_link(invitation)
    unavailable_keyring = AuthenticationLinks::Keyring.new(
      secret_key_base: "replacement-secret-key-base-0123456789abcdef"
    )

    sign_in(@owner)
    with_singleton_method_stub(AuthenticationLinks::Runtime, :keyring, -> { unavailable_keyring }) do
      get project_memberships_path(@project)
    end

    assert_response :success
    assert_select ".form__hint", text: /no longer available/i
    assert_select "form[action='#{project_invitations_path(@project)}']", text: /Reissue/
    assert_select "input[value='#{issued.presentation.url}']", count: 0
  end

  test "non-member cannot view members" do
    other_user = users(:unconfirmed)
    other_user.update!(confirmed_at: Time.current)
    sign_in(other_user)
    get project_memberships_path(@project)
    assert_response :not_found
  end

  # Destroy

  test "owner can remove member" do
    sign_in(@owner)
    assert_difference "ProjectMembership.count", -1 do
      delete project_membership_path(@project, @member_membership)
    end
    assert_redirected_to project_memberships_path(@project)
  end

  test "owner cannot remove self" do
    owner_membership = project_memberships(:alice_owns_alice_project)
    sign_in(@owner)
    assert_no_difference "ProjectMembership.count" do
      delete project_membership_path(@project, owner_membership)
    end
    assert_redirected_to project_memberships_path(@project)
    follow_redirect!
    assert_select ".flash--alert"
  end

  test "member cannot remove others" do
    sign_in(@member)
    assert_no_difference "ProjectMembership.count" do
      delete project_membership_path(@project, project_memberships(:alice_owns_alice_project))
    end
    assert_redirected_to projects_path
  end

  test "a removal authorization race redirects away from the project" do
    sign_in(@owner)
    result = removal_result(:forbidden)

    with_singleton_method_stub(ProjectMemberships::Remove, :call, ->(**) { result }) do
      delete project_membership_path(@project, @member_membership)
    end

    assert_redirected_to projects_path
    assert_equal "Only project owners can remove members.", flash[:alert]
  end

  test "a missing membership returns not found" do
    sign_in(@owner)

    delete project_membership_path(@project, 0)

    assert_response :not_found
  end

  test "a failed membership destroy shows its validation errors" do
    sign_in(@owner)
    @member_membership.errors.add(:base, "Membership could not be removed")
    result = removal_result(:invalid, membership: @member_membership)

    with_singleton_method_stub(ProjectMemberships::Remove, :call, ->(**) { result }) do
      delete project_membership_path(@project, @member_membership)
    end

    assert_redirected_to project_memberships_path(@project)
    assert_equal "Membership could not be removed", flash[:alert]
  end

  test "a busy membership removal asks the owner to retry" do
    sign_in(@owner)
    result = removal_result(:retryable_busy)

    with_singleton_method_stub(ProjectMemberships::Remove, :call, ->(**) { result }) do
      delete project_membership_path(@project, @member_membership)
    end

    assert_redirected_to project_memberships_path(@project)
    assert_equal "Member removal is busy. Please try again.", flash[:alert]
  end

  test "an unexpected membership removal result fails closed" do
    sign_in(@owner)
    result = removal_result(:unexpected)

    with_singleton_method_stub(ProjectMemberships::Remove, :call, ->(**) { result }) do
      delete project_membership_path(@project, @member_membership)
    end

    assert_redirected_to project_memberships_path(@project)
    assert_equal "Member could not be removed.", flash[:alert]
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
        expires_at: 7.days.from_now
      )
    end
  end

  def removal_result(status, membership: nil)
    ProjectMemberships::Remove::Result.new(status: status, membership: membership)
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
