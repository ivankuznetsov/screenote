# frozen_string_literal: true

# screenote-edition: self_hosted

require "test_helper"
require_relative "../support/deterministic_concurrency_test_helper"

class InvitationAcceptanceConcurrencyTest < ActiveSupport::TestCase
  include DeterministicConcurrencyTestHelper
  self.use_transactional_tests = false

  SECRET = "invitation-acceptance-concurrency-secret-012345678"
  Deployment = Data.define(:billing?)

  setup do
    @keyring = AuthenticationLinks::Keyring.new(secret_key_base: SECRET)
    @issuer = AuthenticationLinks::Issuer.new(
      origin: "https://screenote.example.test",
      keyring: @keyring
    )
    @resolver = AuthenticationLinks::Resolver.new(keyring: @keyring)
    @deployment = Deployment.new(billing?: false)
  end

  teardown do
    AuthenticationToken.delete_all
  end

  test "two connections consuming one invitation have exactly one winner" do
    invitation = project_invitations(:pending_invitation)
    user = create_user(invitation.email, "shared-password")
    token = issue_token(invitation)
    proof = ProjectInvitations::IdentityProof.session(user: user)

    accept = lambda do
      ProjectInvitations::Accept.call(
        token_id: token.id,
        proof: proof,
        resolver: @resolver,
        deployment: @deployment
      )
    end

    outcomes = with_invitation_acceptance_barrier(invitation) do |entered, release|
      run_blocked_race(entered: entered, release: release, first: accept, second: accept)
    end

    assert_no_concurrency_exceptions(outcomes)
    assert_equal %i[accepted already_used], outcomes.map(&:status)
    assert_equal 1, invitation.project.project_memberships.where(user: user).count
    assert invitation.reload.accepted?
    assert token.reload.consumed?
  end

  test "different-project local acceptances create one user and require a session for the loser" do
    email = "same-password-race@example.test"
    invitations = invitations_for_two_projects(email)
    tokens = invitations.map { |invitation| issue_token(invitation) }

    accept = lambda do |index|
      ProjectInvitations::Accept.call(
        token_id: tokens.fetch(index).id,
        proof: ProjectInvitations::IdentityProof.local(
          password: "shared-password",
          password_confirmation: "shared-password"
        ),
        resolver: @resolver,
        deployment: @deployment
      )
    end

    outcomes = with_new_user_save_barrier(email) do |entered, release|
      run_blocked_race(
        entered: entered,
        release: release,
        first: -> { accept.call(0) },
        second: -> { accept.call(1) }
      )
    end

    assert_no_concurrency_exceptions(outcomes)
    assert_equal %i[accepted authentication_required], outcomes.map(&:status)
    user = User.find_by!(email: email)
    assert user.authenticate("shared-password")
    assert_equal 1, ProjectMembership.where(user: user, project: invitations.map(&:project)).count
    assert_equal 1, invitations.count { |invitation| invitation.reload.accepted? }
    assert_equal 1, tokens.count { |token| token.reload.consumed? }

    pending_invitation = invitations.find { |invitation| invitation.reload.pending? }
    pending_index = invitations.index(pending_invitation)
    continued = ProjectInvitations::Accept.call(
      token_id: tokens.fetch(pending_index).id,
      proof: ProjectInvitations::IdentityProof.session(user: user),
      resolver: @resolver,
      deployment: @deployment
    )

    assert_equal :accepted, continued.status
    assert_equal 2, ProjectMembership.where(user: user, project: invitations.map(&:project)).count
    assert invitations.all? { |invitation| invitation.reload.accepted? }
    assert tokens.all? { |token| token.reload.consumed? }
  end

  test "different-project loser cannot claim the committed user through the local form" do
    email = "different-password-race@example.test"
    invitations = invitations_for_two_projects(email)
    tokens = invitations.map { |invitation| issue_token(invitation) }
    passwords = %w[first-password second-password]

    accept = lambda do |index|
      password = passwords.fetch(index)
      ProjectInvitations::Accept.call(
        token_id: tokens.fetch(index).id,
        proof: ProjectInvitations::IdentityProof.local(
          password: password,
          password_confirmation: password
        ),
        resolver: @resolver,
        deployment: @deployment
      )
    end

    outcomes = with_new_user_save_barrier(email) do |entered, release|
      run_blocked_race(
        entered: entered,
        release: release,
        first: -> { accept.call(0) },
        second: -> { accept.call(1) }
      )
    end

    assert_no_concurrency_exceptions(outcomes)
    assert_equal %i[accepted authentication_required], outcomes.map(&:status)
    user = User.find_by!(email: email)
    assert user.authenticate(passwords.first)
    assert_not user.authenticate(passwords.second)
    assert_equal 1, ProjectMembership.where(user: user, project: invitations.map(&:project)).count
    assert_equal 1, invitations.count { |invitation| invitation.reload.accepted? }
    assert_equal 1, tokens.count { |token| token.reload.consumed? }

    pending_invitation = invitations.find { |invitation| invitation.reload.pending? }
    pending_index = invitations.index(pending_invitation)
    pending_token = tokens.fetch(pending_index)
    passwords.each do |password|
      local_retry = ProjectInvitations::Accept.call(
        token_id: pending_token.id,
        proof: ProjectInvitations::IdentityProof.local(password: password, password_confirmation: password),
        resolver: @resolver,
        deployment: @deployment
      )

      assert_equal :authentication_required, local_retry.status
      assert pending_invitation.reload.pending?
      assert pending_token.reload.outstanding?
    end

    continued = ProjectInvitations::Accept.call(
      token_id: pending_token.id,
      proof: ProjectInvitations::IdentityProof.session(user: user),
      resolver: @resolver,
      deployment: @deployment
    )

    assert_equal :accepted, continued.status
    assert_equal 2, ProjectMembership.where(user: user, project: invitations.map(&:project)).count
    assert invitations.all? { |invitation| invitation.reload.accepted? }
    assert tokens.all? { |token| token.reload.consumed? }
  end

  test "cancellation racing acceptance leaves one coherent terminal outcome" do
    invitation = project_invitations(:pending_invitation)
    token = issue_token(invitation)
    principal = AuthenticatedPrincipal.for_user(invitation.inviter)

    accept = lambda do
      ProjectInvitations::Accept.call(
        token_id: token.id,
        proof: ProjectInvitations::IdentityProof.local(
          password: "new-password",
          password_confirmation: "new-password"
        ),
        resolver: @resolver,
        deployment: @deployment
      )
    end
    cancel = lambda do
      ProjectInvitations::Cancel.call(
        principal: principal,
        project: invitation.project,
        invitation_id: invitation.id
      )
    end

    outcomes = with_invitation_acceptance_barrier(invitation) do |entered, release|
      run_blocked_race(entered: entered, release: release, first: accept, second: cancel)
    end

    assert_no_concurrency_exceptions(outcomes)
    assert_equal %i[accepted already_accepted], outcomes.map(&:status)
    assert invitation.reload.accepted?
    assert token.reload.consumed?
    assert User.exists?(email: invitation.email)
  end

  private

  def invitations_for_two_projects(email)
    [
      projects(:alice_second_project).project_invitations.create!(inviter: users(:alice), email: email),
      projects(:bob_project).project_invitations.create!(inviter: users(:bob), email: email)
    ]
  end

  def issue_token(invitation)
    token = nil
    ProjectInvitation.transaction do
      token = @issuer.call(
        purpose: :invitation,
        subject: ProjectInvitation.lock.find(invitation.id),
        expires_at: 7.days.from_now
      ).token
    end
    token
  end

  def create_user(email, password)
    User.create!(email: email, password: password, confirmed_at: Time.current)
  end

  def with_invitation_acceptance_barrier(invitation, &block)
    with_one_shot_instance_method_barrier(
      ProjectInvitation,
      :update_columns,
      predicate: lambda do |record, attributes = {}, **keyword_attributes|
        attributes = keyword_attributes if attributes.empty?
        record.id == invitation.id && attributes[:status] == ProjectInvitation.statuses.fetch(:accepted)
      end,
      &block
    )
  end

  def with_new_user_save_barrier(email, &block)
    with_one_shot_instance_method_barrier(
      User,
      :save!,
      predicate: ->(record, *) { record.new_record? && record.email == email },
      &block
    )
  end
end
