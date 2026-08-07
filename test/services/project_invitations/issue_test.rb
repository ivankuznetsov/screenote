# frozen_string_literal: true

require "test_helper"

module ProjectInvitations
  class IssueTest < ActiveSupport::TestCase
    self.use_transactional_tests = false

    SECRET = "project-invitation-issue-test-secret-0123456789"
    ORIGIN = "https://screenote.example.test"
    NOW = Time.utc(2026, 8, 5, 12)

    Deployment = Data.define(:billing?, :mail?)

    setup do
      @owner = users(:alice)
      @project = projects(:alice_project)
      @principal = AuthenticatedPrincipal.for_user(@owner)
      @keyring = AuthenticationLinks::Keyring.new(secret_key_base: SECRET)
      @issuer = AuthenticationLinks::Issuer.new(origin: ORIGIN, keyring: @keyring, clock: -> { NOW })
    end

    teardown do
      AuthenticationToken.delete_all
    end

    test "issues and safely re-presents one pending invitation credential" do
      issued = issue(email: " Invitee@Example.test ")

      assert_equal :issued, issued.status
      assert_predicate issued, :success?
      assert_equal "invitee@example.test", issued.invitation.email
      assert issued.token.outstanding?
      assert_equal issued.token, issued.invitation.authentication_tokens.first
      assert_equal ORIGIN, issued.presentation.origin

      repeated = issue(email: "invitee@example.test")

      assert_equal :already_pending, repeated.status
      assert_predicate repeated, :success?
      assert_equal issued.invitation, repeated.invitation
      assert_equal issued.token, repeated.token
      assert_equal issued.presentation.fragment, repeated.presentation.fragment
      assert_equal 1, issued.invitation.authentication_tokens.count
    end

    test "reissues an expired pending credential without deleting the invitation" do
      issued = issue(email: "expiring@example.test", expires_at: NOW + 1.minute)
      later_issuer = AuthenticationLinks::Issuer.new(
        origin: ORIGIN,
        keyring: @keyring,
        clock: -> { NOW + 2.minutes }
      )

      reissued = issue(
        email: "expiring@example.test",
        authentication_link_issuer: later_issuer,
        clock: -> { NOW + 2.minutes }
      )

      assert_equal :reissued, reissued.status
      assert_equal issued.invitation, reissued.invitation
      assert issued.token.reload.superseded?
      assert_equal 2, reissued.token.generation
      assert reissued.token.outstanding?
    end

    test "reissues when a pending invitation has no outstanding grant" do
      issued = issue(email: "consumed@example.test")
      issued.token.update_columns(
        state: AuthenticationToken.states.fetch(:consumed),
        terminal_at: NOW
      )

      reissued = issue(email: issued.invitation.email)

      assert_equal :reissued, reissued.status
      assert_equal issued.invitation, reissued.invitation
      assert issued.token.reload.consumed?
      assert reissued.token.outstanding?
      assert_equal 2, reissued.token.generation
    end

    test "the class entrypoint constructs its default authentication-link issuer" do
      issuer = @issuer
      original = AuthenticationLinks::Issuer.method(:new)
      constructor_arguments = []
      AuthenticationLinks::Issuer.define_singleton_method(:new) do |origin:, keyring:, clock:|
        constructor_arguments << [ origin, keyring, clock ]
        issuer
      end

      result = Issue.call(
        principal: @principal,
        project: @project,
        email: "default-issuer@example.test",
        deployment: Deployment.new(billing?: false, mail?: false),
        clock: -> { NOW }
      )

      assert_equal :issued, result.status
      assert_equal 1, constructor_arguments.size
      assert constructor_arguments.dig(0, 0)
      assert constructor_arguments.dig(0, 1)
      assert constructor_arguments.dig(0, 2)
    ensure
      AuthenticationLinks::Issuer.define_singleton_method(:new, original) if original
    end

    test "returns stable authorization identity membership and validation results" do
      forbidden = Issue.call(
        principal: AuthenticatedPrincipal.for_user(users(:bob)),
        project: @project,
        email: "forbidden@example.test",
        authentication_link_issuer: @issuer,
        deployment: Deployment.new(billing?: false, mail?: false),
        clock: -> { NOW }
      )
      assert_equal :forbidden, forbidden.status

      stale_principal = @principal
      @owner.update!(access_status: :suspended)
      inactive = issue(email: "inactive@example.test", principal: stale_principal)
      assert_equal :inactive_issuer, inactive.status
      @owner.update!(access_status: :active)

      assert_equal :already_member, issue(email: users(:bob).email).status
      invalid = issue(email: "not-an-email")
      assert_equal :invalid, invalid.status
      assert_not_predicate invalid, :success?
      assert_equal :invalid, issue(email: nil).status
      assert_equal :not_found, issue(email: "missing@example.test", project: Project.new).status
      assert_equal :not_found, issue(email: "nil-project@example.test", project: nil).status

      deleted_project = Project.create!(creator: @owner, name: "Deleted project")
      deleted_project.destroy!
      assert_equal :not_found,
        issue(email: "deleted-project@example.test", project: deleted_project).status

      api_principal = AuthenticatedPrincipal.for_api_key(api_keys(:alice_key))
      assert_equal :forbidden,
        issue(email: "api-key@example.test", principal: api_principal).status

      read_only = AuthenticatedPrincipal.new(
        kind: :user,
        user: @owner,
        issuer: @owner,
        scopes: [ AuthenticatedPrincipal::READ_SCOPE ]
      )
      assert_equal :forbidden,
        issue(email: "read-only@example.test", principal: read_only).status
      assert_equal :forbidden,
        issue(email: "missing-principal@example.test", principal: nil).status
    end

    test "fails closed if the project creator changes outside the authority lock protocol" do
      original = AuthorityLock.method(:users!)
      project = @project
      replacement = User.create!(
        email: "replacement-creator@example.test",
        password: "password123",
        confirmed_at: Time.current
      )
      AuthorityLock.define_singleton_method(:users!) do |users|
        locked = original.call(users)
        project.update_columns(user_id: replacement.id)
        locked
      end

      result = issue(email: "creator-race@example.test")

      assert_equal :not_found, result.status
      assert_not ProjectInvitation.exists?(project_id: project.id, email: "creator-race@example.test")
    ensure
      AuthorityLock.define_singleton_method(:users!, original) if original
      project&.update_columns(user_id: @owner.id)
      replacement&.destroy!
    end

    test "fails closed if an invitation issuer was not included in the authority lock set" do
      original = AuthorityLock.method(:users!)
      project = @project
      email = "issuer-lock-race@example.test"
      replacement_inviter = users(:bob)
      raced_invitation = nil
      AuthorityLock.define_singleton_method(:users!) do |users|
        locked = original.call(users)
        raced_invitation = ProjectInvitation.create!(
          project: project,
          inviter: replacement_inviter,
          email: email,
          status: :cancelled
        )
        locked
      end

      result = issue(email: email)

      assert_equal :not_found, result.status
      assert_not ProjectInvitation.pending.exists?(project_id: project.id, email: email)
    ensure
      AuthorityLock.define_singleton_method(:users!, original) if original
      raced_invitation&.destroy!
    end

    test "enforces SaaS member quota while self-hosted remains unlimited" do
      free_owner = users(:bob)
      free_project = projects(:bob_project)
      member = User.create!(
        email: "quota-member@example.test",
        password: "password123",
        confirmed_at: Time.current
      )
      free_project.project_memberships.create!(user: member, role: :member)
      principal = AuthenticatedPrincipal.for_user(free_owner)

      below_limit_owner = User.create!(
        email: "below-limit-owner@example.test",
        password: "password123",
        confirmed_at: Time.current
      )
      below_limit_project = Project.create!(creator: below_limit_owner, name: "Below limit")
      below_limit = issue(
        principal: AuthenticatedPrincipal.for_user(below_limit_owner),
        project: below_limit_project,
        email: "below-limit@example.test",
        deployment: Deployment.new(billing?: true, mail?: false)
      )

      limited = issue(
        principal: principal,
        project: free_project,
        email: "limited@example.test",
        deployment: Deployment.new(billing?: true, mail?: false)
      )
      unlimited = issue(
        principal: principal,
        project: free_project,
        email: "unlimited@example.test",
        deployment: Deployment.new(billing?: false, mail?: false)
      )

      assert_equal :issued, below_limit.status
      assert_equal :limit_reached, limited.status
      assert_equal :issued, unlimited.status

      pro_result = issue(
        email: "pro-owner@example.test",
        deployment: Deployment.new(billing?: true, mail?: false)
      )
      assert_equal :issued, pro_result.status
    end

    test "cancels a pending grant from a revoked issuer before an active owner reissues it" do
      original = issue(email: "revoked-issuer@example.test")
      bob_membership = @project.project_memberships.find_by!(user: users(:bob))
      bob_membership.update!(role: :owner)
      @owner.update!(access_status: :suspended)

      replacement = issue(
        email: original.invitation.email,
        principal: AuthenticatedPrincipal.for_user(users(:bob))
      )

      assert_equal :reissued, replacement.status
      assert_not_equal original.invitation, replacement.invitation
      assert original.invitation.reload.cancelled?
      assert original.token.reload.cancelled?
      assert replacement.invitation.pending?
      assert replacement.token.outstanding?
    end

    test "owner loss cancels the invitation but preserves a consumed grant" do
      original = issue(email: "demoted-issuer@example.test")
      bob = users(:bob)
      @project.project_memberships.find_by!(user: bob).update!(role: :owner)
      @project.project_memberships.find_by!(user: @owner).update!(role: :member)
      original.token.update_columns(
        state: AuthenticationToken.states.fetch(:consumed),
        terminal_at: NOW
      )

      replacement = issue(
        email: original.invitation.email,
        principal: AuthenticatedPrincipal.for_user(bob)
      )

      assert_equal :reissued, replacement.status
      assert original.invitation.reload.cancelled?
      assert original.token.reload.consumed?
      assert replacement.token.outstanding?
    end

    test "queues mail after commit with IDs only" do
      calls = []
      delivery = Object.new
      delivery.define_singleton_method(:deliver_later) do
        calls << [ :deliver_later, ApplicationRecord.connection.transaction_open? ]
      end
      mailer = Object.new
      mailer.define_singleton_method(:invite) do |invitation_id, token_id|
        calls << [ :invite, invitation_id, token_id, ApplicationRecord.connection.transaction_open? ]
        delivery
      end

      result = issue(
        email: "mailed@example.test",
        deployment: Deployment.new(billing?: false, mail?: true),
        mailer: mailer
      )

      assert_equal :issued, result.status
      assert_equal :queued, result.delivery_status
      assert_equal [ :invite, result.invitation.id, result.token.id, false ], calls.first
      assert_equal [ :deliver_later, false ], calls.second
    end

    test "does not redeliver mail when representing an existing grant" do
      issued = issue(email: "represented@example.test")
      calls = []
      mailer = Object.new
      mailer.define_singleton_method(:invite) do |*arguments|
        calls << arguments
        raise "should not enqueue"
      end

      represented = issue(
        email: issued.invitation.email,
        deployment: Deployment.new(billing?: false, mail?: true),
        mailer: mailer
      )

      assert_equal :already_pending, represented.status
      assert_equal :not_requested, represented.delivery_status
      assert_empty calls
    end

    test "mail delivery failures are reported without undoing issued credentials" do
      delivery_error = StandardError.new("mail unavailable")
      delivery = Object.new
      delivery.define_singleton_method(:deliver_later) { raise delivery_error }
      mailer = Object.new
      mailer.define_singleton_method(:invite) { |*, **| delivery }
      notifications = []
      original = Screenote::Monitoring.method(:notify)
      Screenote::Monitoring.define_singleton_method(:notify) do |error, context:|
        notifications << [ error, context ]
      end

      result = issue(
        email: "mail-failure@example.test",
        deployment: Deployment.new(billing?: false, mail?: true),
        mailer: mailer
      )

      assert_equal :issued, result.status
      assert_equal :failed, result.delivery_status
      assert result.token.reload.outstanding?
      assert_equal delivery_error, notifications.dig(0, 0)
      assert_equal result.invitation.id, notifications.dig(0, 1, :invitation_id)
      assert_equal result.token.id, notifications.dig(0, 1, :authentication_token_id)
    ensure
      Screenote::Monitoring.define_singleton_method(:notify, original) if original
    end

    test "database exhaustion validation and uniqueness races return frozen result envelopes" do
      exhausted = DatabaseRetry::Exhausted.new(StandardError.new("busy"), attempts: 3)
      busy = issue_with_database_error(exhausted)
      assert_equal :retryable_busy, busy.status
      assert busy.errors.frozen?

      invalid_invitation = ProjectInvitation.new(project: @project, inviter: @owner, email: "bad")
      invalid_invitation.validate
      invalid = issue_with_database_error(ActiveRecord::RecordInvalid.new(invalid_invitation))
      assert_equal :invalid, invalid.status
      assert_equal invalid_invitation, invalid.invitation
      assert_predicate invalid.errors, :any?
      assert invalid.errors.frozen?

      invalid_user = User.new
      invalid_user.validate
      unrelated = issue_with_database_error(ActiveRecord::RecordInvalid.new(invalid_user))
      assert_equal :invalid, unrelated.status
      assert_nil unrelated.invitation
      assert_predicate unrelated.errors, :any?

      collision = issue_with_database_error(ActiveRecord::RecordNotUnique.new("collision"))
      assert_equal :invalid, collision.status
      assert_nil collision.invitation
    end

    private

    def issue(
      email:,
      principal: @principal,
      project: @project,
      authentication_link_issuer: @issuer,
      deployment: Deployment.new(billing?: false, mail?: false),
      clock: -> { NOW },
      expires_at: nil,
      mailer: ProjectInvitationMailer
    )
      Issue.call(
        principal: principal,
        project: project,
        email: email,
        authentication_link_issuer: authentication_link_issuer,
        deployment: deployment,
        clock: clock,
        expires_at: expires_at,
        mailer: mailer
      )
    end


    def issue_with_database_error(error)
      original = DatabaseRetry.method(:call)
      DatabaseRetry.define_singleton_method(:call) { |**| raise error }
      issue(email: "database-error@example.test")
    ensure
      DatabaseRetry.define_singleton_method(:call, original)
    end
  end
end
