# frozen_string_literal: true

require "test_helper"

module ProjectInvitations
  class AcceptTest < ActiveSupport::TestCase
    self.use_transactional_tests = false

    SECRET = "project-invitation-accept-test-secret-012345678"
    ORIGIN = "https://screenote.example.test"
    NOW = Time.utc(2026, 8, 5, 12)

    Deployment = Data.define(:billing?)

    setup do
      @invitation = project_invitations(:pending_invitation)
      @project = @invitation.project
      @keyring = AuthenticationLinks::Keyring.new(secret_key_base: SECRET)
      @issuer = AuthenticationLinks::Issuer.new(origin: ORIGIN, keyring: @keyring, clock: -> { NOW })
      @resolver = AuthenticationLinks::Resolver.new(keyring: @keyring, clock: -> { NOW })
      @token = issue_token(@invitation).token
    end

    teardown do
      AuthenticationToken.delete_all
    end

    test "accepts a matching active session and consumes the grant atomically" do
      user = create_user(@invitation.email)

      result = accept(IdentityProof.session(user: user))

      assert_equal :accepted, result.status, result.inspect
      assert_predicate result, :success?
      assert_equal user, result.user
      assert_equal @project, result.project
      assert @project.project_memberships.exists?(user: user, role: :member)
      assert @invitation.reload.accepted?
      assert @token.reload.consumed?
    end

    test "rejects a different signed-in identity without mutating the grant" do
      membership_count = @project.project_memberships.count
      result = accept(IdentityProof.session(user: users(:bob)))

      assert_equal :identity_mismatch, result.status
      assert @invitation.reload.pending?
      assert @token.reload.outstanding?
      assert_equal membership_count, @project.project_memberships.count
    end

    test "creates confirmed durable local credentials only while accepting" do
      proof = IdentityProof.local(password: "new-password", password_confirmation: "new-password")

      assert_difference [ "User.count", "ProjectMembership.count" ], 1 do
        result = accept(proof)
        assert_equal :accepted, result.status, result.inspect
      end

      user = User.find_by!(email: @invitation.email)
      assert user.authenticate("new-password")
      assert user.confirmed_at.present?
      assert user.active?
      assert @project.member?(user)
    end

    test "returns invitation context and validation errors for retryable local input" do
      result = accept(
        IdentityProof.local(password: "new-password", password_confirmation: "different-password")
      )

      assert_equal :invalid_input, result.status
      assert_equal @invitation, result.invitation
      assert_equal @project, result.project
      assert_includes result.errors.to_sentence, "doesn't match"
      assert @invitation.reload.pending?
      assert @token.reload.outstanding?
      assert_nil User.find_by(email: @invitation.email)
    end

    test "rejects missing malformed and empty identity proofs before mutation" do
      assert_equal :authentication_required, accept(nil).status
      assert_equal :invalid_identity, accept(Object.new).status
      assert_equal :invalid_identity, accept(IdentityProof.session(user: nil)).status
      assert_equal :invalid_input, accept(IdentityProof.local(password: "")).status

      malformed = Accept.call(
        token_id: @token.id.to_s,
        proof: IdentityProof.local(password: "new-password", password_confirmation: "new-password"),
        resolver: @resolver,
        deployment: Deployment.new(billing?: false),
        clock: -> { NOW }
      )
      assert_equal :invalid, malformed.status

      zero = Accept.call(
        token_id: 0,
        proof: IdentityProof.local(password: "new-password"),
        resolver: @resolver,
        deployment: Deployment.new(billing?: false),
        clock: -> { NOW }
      )
      assert_equal :invalid, zero.status

      absent = Accept.call(
        token_id: @token.id + 10_000,
        proof: IdentityProof.local(password: "new-password"),
        resolver: @resolver,
        deployment: Deployment.new(billing?: false),
        clock: -> { NOW }
      )
      assert_equal :invalid, absent.status
      assert_nil absent.invitation
      assert_not_predicate absent, :success?
      assert @invitation.reload.pending?
      assert @token.reload.outstanding?
    end

    test "the class entrypoint constructs its default resolver" do
      user = create_user(@invitation.email)
      resolver = @resolver
      original = AuthenticationLinks::Resolver.method(:new)
      constructor_arguments = []
      AuthenticationLinks::Resolver.define_singleton_method(:new) do |keyring:, clock:|
        constructor_arguments << [ keyring, clock ]
        resolver
      end

      result = Accept.call(
        token_id: @token.id,
        proof: IdentityProof.session(user: user),
        deployment: Deployment.new(billing?: false),
        clock: -> { NOW }
      )

      assert_equal :accepted, result.status
      assert_equal 1, constructor_arguments.size
      assert constructor_arguments.dig(0, 0)
      assert constructor_arguments.dig(0, 1)
    ensure
      AuthenticationLinks::Resolver.define_singleton_method(:new, original) if original
    end

    test "requires an existing local user to authenticate through the normal session flow" do
      user = create_user(@invitation.email)

      wrong = accept(IdentityProof.local(password: "wrong-password"))
      assert_equal :authentication_required, wrong.status
      assert @invitation.reload.pending?
      assert_not @project.member?(user)

      correct = accept(IdentityProof.local(password: "password123"))
      assert_equal :authentication_required, correct.status
      assert @invitation.reload.pending?
      assert_not @project.member?(user)

      accepted = accept(IdentityProof.session(user: user))
      assert_equal :accepted, accepted.status
      assert_equal user, accepted.user
    end

    test "rejects every proof kind when its existing identity is suspended" do
      user = create_user(@invitation.email)
      user.update!(
        access_status: :suspended,
        oauth_provider: "google_oauth2",
        oauth_uid: "suspended-provider"
      )

      assert_equal :invalid_identity, accept(IdentityProof.session(user: user)).status
      assert_equal :invalid_identity, accept(IdentityProof.local(password: "password123")).status
      assert_equal :invalid_identity,
        accept(google_proof(email: @invitation.email, uid: "suspended-provider")).status
      assert @invitation.reload.pending?
      assert @token.reload.outstanding?
    end

    test "local proofs cannot turn multiple invitation links into password oracles" do
      user = create_user(@invitation.email)
      other_project = projects(:bob_project)
      other_invitation = other_project.project_invitations.create!(
        inviter: users(:bob),
        email: user.email
      )
      other_token = issue_token(other_invitation).token

      [ @token, other_token ].each do |token|
        %w[wrong-password password123].each do |guess|
          result = Accept.call(
            token_id: token.id,
            proof: IdentityProof.local(password: guess),
            resolver: @resolver,
            deployment: Deployment.new(billing?: false),
            clock: -> { NOW }
          )

          assert_equal :authentication_required, result.status
          assert token.reload.outstanding?
        end
      end

      assert_not @project.member?(user)
      assert_not other_project.member?(user)
    end

    test "creates a provider identity only from the provider-specific verified email contract" do
      proof = google_proof(email: @invitation.email, uid: "google-invitee")

      result = accept(proof)

      assert_equal :accepted, result.status
      assert_equal "google_oauth2", result.user.oauth_provider
      assert_equal "google-invitee", result.user.oauth_uid
      assert_equal @invitation.email, result.user.email
    end

    test "requires exact provider identity for an existing address" do
      local_user = create_user(@invitation.email)

      result = accept(google_proof(email: @invitation.email, uid: "unbound-provider"))

      assert_equal :invalid_identity, result.status
      assert @invitation.reload.pending?
      assert_not @project.member?(local_user)

      local_user.update!(oauth_provider: "google_oauth2", oauth_uid: "bound-provider")
      accepted = accept(google_proof(email: @invitation.email, uid: "bound-provider"))
      assert_equal :accepted, accepted.status
      assert_equal local_user, accepted.user
    end

    test "rejects a provider subject already bound to another address" do
      provider_user = create_user("provider-owner@example.test")
      provider_user.update!(oauth_provider: "google_oauth2", oauth_uid: "owned-provider")

      result = accept(google_proof(email: @invitation.email, uid: "owned-provider"))

      assert_equal :identity_mismatch, result.status
      assert @invitation.reload.pending?
      assert @token.reload.outstanding?
      assert_not @project.member?(provider_user)
    end

    test "rejects unverified or mismatched provider email" do
      unverified = IdentityProof.provider(
        "provider" => "google_oauth2",
        "uid" => "uid",
        "info" => { "email" => @invitation.email, "email_verified" => false }
      )

      assert_equal :invalid_identity, accept(unverified).status
      assert_equal :identity_mismatch,
        accept(google_proof(email: "different@example.test", uid: "different")).status
      assert @invitation.reload.pending?
    end

    test "maps every terminal token state without creating a user or membership" do
      {
        consumed: :already_used,
        superseded: :superseded,
        cancelled: :cancelled
      }.each do |state, expected|
        reset_grant(state)

        assert_no_difference [ "User.count", "ProjectMembership.count" ] do
          assert_equal expected,
            accept(IdentityProof.local(password: "new-password", password_confirmation: "new-password")).status
        end
      end

      reset_grant(:outstanding)
      later_resolver = AuthenticationLinks::Resolver.new(keyring: @keyring, clock: -> { NOW + 8.days })
      assert_equal :expired,
        accept(
          IdentityProof.local(password: "new-password", password_confirmation: "new-password"),
          resolver: later_resolver,
          clock: -> { NOW + 8.days }
        ).status
    end

    test "terminal invitation races discard provisional users and terminalize outstanding tokens" do
      @invitation.update_columns(status: ProjectInvitation.statuses.fetch(:cancelled))

      assert_no_difference [ "User.count", "ProjectMembership.count" ] do
        result = accept(IdentityProof.local(password: "new-password", password_confirmation: "new-password"))
        assert_equal :cancelled, result.status
      end
      assert @token.reload.cancelled?
    end

    test "accepted invitation race discards the provisional user and consumes an outstanding token" do
      @invitation.update_columns(status: ProjectInvitation.statuses.fetch(:accepted))

      assert_no_difference [ "User.count", "ProjectMembership.count" ] do
        result = accept(IdentityProof.local(password: "new-password", password_confirmation: "new-password"))
        assert_equal :already_used, result.status
      end
      assert @token.reload.consumed?
    end

    test "a terminal invitation race does not discard an existing identity" do
      user = create_user(@invitation.email)
      @invitation.update_columns(status: ProjectInvitation.statuses.fetch(:accepted))

      result = accept(IdentityProof.session(user: user))

      assert_equal :already_used, result.status
      assert User.exists?(user.id)
      assert @token.reload.consumed?
    end

    test "a terminal invitation race tolerates a grant deleted after preflight" do
      underlying = @resolver
      token = @token
      first_call = true
      @invitation.update_columns(status: ProjectInvitation.statuses.fetch(:cancelled))
      racing_resolver = Object.new
      racing_resolver.define_singleton_method(:revalidate) do |**arguments|
        resolution = underlying.revalidate(**arguments)
        if first_call
          first_call = false
          token.delete
        end
        resolution
      end

      assert_no_difference [ "User.count", "ProjectMembership.count" ] do
        result = accept(
          IdentityProof.local(password: "new-password", password_confirmation: "new-password"),
          resolver: racing_resolver
        )
        assert_equal :cancelled, result.status
      end
    end

    test "an accepted invitation race tolerates a grant deleted after preflight" do
      underlying = @resolver
      token = @token
      first_call = true
      @invitation.update_columns(status: ProjectInvitation.statuses.fetch(:accepted))
      racing_resolver = Object.new
      racing_resolver.define_singleton_method(:revalidate) do |**arguments|
        resolution = underlying.revalidate(**arguments)
        if first_call
          first_call = false
          token.delete
        end
        resolution
      end

      assert_no_difference [ "User.count", "ProjectMembership.count" ] do
        result = accept(
          IdentityProof.local(password: "new-password", password_confirmation: "new-password"),
          resolver: racing_resolver
        )
        assert_equal :already_used, result.status
      end
      assert_not AuthenticationToken.exists?(token.id)
    end

    test "a cancelled invitation preserves a grant cancelled after preflight" do
      underlying = @resolver
      token = @token
      first_call = true
      @invitation.update_columns(status: ProjectInvitation.statuses.fetch(:cancelled))
      racing_resolver = Object.new
      racing_resolver.define_singleton_method(:revalidate) do |**arguments|
        resolution = underlying.revalidate(**arguments)
        if first_call
          first_call = false
          token.update_columns(
            state: AuthenticationToken.states.fetch(:cancelled),
            terminal_at: NOW
          )
        end
        resolution
      end

      result = accept(
        IdentityProof.local(password: "new-password", password_confirmation: "new-password"),
        resolver: racing_resolver
      )

      assert_equal :cancelled, result.status
      assert @token.reload.cancelled?
      assert_nil User.find_by(email: @invitation.email)
    end

    test "an accepted invitation preserves a grant consumed after preflight" do
      underlying = @resolver
      token = @token
      first_call = true
      @invitation.update_columns(status: ProjectInvitation.statuses.fetch(:accepted))
      racing_resolver = Object.new
      racing_resolver.define_singleton_method(:revalidate) do |**arguments|
        resolution = underlying.revalidate(**arguments)
        if first_call
          first_call = false
          token.update_columns(
            state: AuthenticationToken.states.fetch(:consumed),
            terminal_at: NOW
          )
        end
        resolution
      end

      result = accept(
        IdentityProof.local(password: "new-password", password_confirmation: "new-password"),
        resolver: racing_resolver
      )

      assert_equal :already_used, result.status
      assert @token.reload.consumed?
      assert_nil User.find_by(email: @invitation.email)
    end

    test "an existing membership is not duplicated while its invitation is consumed" do
      user = create_user(@invitation.email)
      @project.project_memberships.create!(user: user, role: :member)

      assert_no_difference "ProjectMembership.count" do
        result = accept(IdentityProof.session(user: user))
        assert_equal :accepted, result.status
        assert_equal user, result.user
      end
      assert @invitation.reload.accepted?
      assert @token.reload.consumed?
    end

    test "cancels the grant when its issuing owner is no longer active" do
      @invitation.inviter.update!(access_status: :suspended)

      result = accept(IdentityProof.local(password: "new-password", password_confirmation: "new-password"))

      assert_equal :issuer_revoked, result.status
      assert @invitation.reload.cancelled?
      assert @token.reload.cancelled?
      assert_nil User.find_by(email: @invitation.email)
    end

    test "cancels the grant when its active issuer is no longer an owner" do
      @project.project_memberships.find_by!(user: @invitation.inviter).update!(role: :member)

      result = accept(IdentityProof.local(password: "new-password", password_confirmation: "new-password"))

      assert_equal :issuer_revoked, result.status
      assert @invitation.reload.cancelled?
      assert @token.reload.cancelled?
      assert_nil User.find_by(email: @invitation.email)
    end

    test "issuer revocation preserves a grant consumed after preflight" do
      @invitation.inviter.update!(access_status: :suspended)
      underlying = @resolver
      token = @token
      first_call = true
      racing_resolver = Object.new
      racing_resolver.define_singleton_method(:revalidate) do |**arguments|
        resolution = underlying.revalidate(**arguments)
        if first_call
          first_call = false
          token.update_columns(
            state: AuthenticationToken.states.fetch(:consumed),
            terminal_at: NOW
          )
        end
        resolution
      end

      result = accept(
        IdentityProof.local(password: "new-password", password_confirmation: "new-password"),
        resolver: racing_resolver
      )

      assert_equal :issuer_revoked, result.status
      assert @invitation.reload.cancelled?
      assert @token.reload.consumed?
      assert_nil User.find_by(email: @invitation.email)
    end

    test "issuer revocation tolerates a grant deleted after preflight" do
      @invitation.inviter.update!(access_status: :suspended)
      underlying = @resolver
      token = @token
      first_call = true
      racing_resolver = Object.new
      racing_resolver.define_singleton_method(:revalidate) do |**arguments|
        resolution = underlying.revalidate(**arguments)
        if first_call
          first_call = false
          token.delete
        end
        resolution
      end

      result = accept(
        IdentityProof.local(password: "new-password", password_confirmation: "new-password"),
        resolver: racing_resolver
      )

      assert_equal :issuer_revoked, result.status
      assert @invitation.reload.cancelled?
      assert_not AuthenticationToken.exists?(token.id)
      assert_nil User.find_by(email: @invitation.email)
    end

    test "enforces SaaS quota at acceptance but not in self-hosted mode" do
      owner = users(:bob)
      project = projects(:bob_project)
      invitation = project.project_invitations.create!(
        inviter: owner,
        email: "quota-invitee@example.test"
      )
      token = issue_token(invitation).token
      member = create_user("quota-existing-member@example.test")
      project.project_memberships.create!(user: member, role: :member)
      proof = IdentityProof.local(password: "new-password", password_confirmation: "new-password")

      limited = Accept.call(
        token_id: token.id,
        proof: proof,
        resolver: @resolver,
        deployment: Deployment.new(billing?: true),
        clock: -> { NOW }
      )
      assert_equal :limit_reached, limited.status
      assert invitation.reload.pending?
      assert token.reload.outstanding?

      unlimited = Accept.call(
        token_id: token.id,
        proof: proof,
        resolver: @resolver,
        deployment: Deployment.new(billing?: false),
        clock: -> { NOW }
      )
      assert_equal :accepted, unlimited.status
    end

    test "persists users and memberships before locking the authentication token" do
      statements = []
      subscriber = lambda do |_name, _started, _finished, _unique_id, payload|
        statements << payload.fetch(:sql)
      end

      result = ActiveSupport::Notifications.subscribed(subscriber, "sql.active_record") do
        accept(IdentityProof.local(password: "new-password", password_confirmation: "new-password"))
      end

      user_insert = statements.index { |sql| sql.start_with?('INSERT INTO "users"') }
      project_lock = statements.each_index.find do |index|
        index > user_insert && statements.fetch(index).start_with?('SELECT "projects".* FROM "projects"')
      end
      invitation_lock = statements.each_index.find do |index|
        index > project_lock && statements.fetch(index).start_with?('SELECT "project_invitations".* FROM "project_invitations"')
      end
      membership_insert = statements.index { |sql| sql.start_with?('INSERT INTO "project_memberships"') }
      token_lock = statements.each_index.find do |index|
        index > membership_insert && statements.fetch(index).start_with?('SELECT "authentication_tokens".*')
      end

      assert_equal :accepted, result.status
      assert user_insert < project_lock
      assert project_lock < invitation_lock
      assert invitation_lock < membership_insert
      assert membership_insert < token_lock
    end

    test "a lost token transition rolls back provisional authority and returns a stable result" do
      original = AuthenticationToken.instance_method(:transition_to!)
      AuthenticationToken.define_method(:transition_to!) { |*, **| false }

      result = accept(
        IdentityProof.local(password: "new-password", password_confirmation: "new-password")
      )

      assert_instance_of Accept::Result, result
      assert_equal :retryable_busy, result.status
      assert_nil User.find_by(email: @invitation.email)
      assert @invitation.reload.pending?
      assert @token.reload.outstanding?
    ensure
      AuthenticationToken.define_method(:transition_to!, original)
    end

    test "a terminal revalidation race rolls back provisional authority" do
      underlying = @resolver
      token = @token
      calls = 0
      racing_resolver = Object.new
      racing_resolver.define_singleton_method(:revalidate) do |**arguments|
        calls += 1
        if calls == 2
          token.update_columns(
            state: AuthenticationToken.states.fetch(:cancelled),
            terminal_at: NOW
          )
        end
        underlying.revalidate(**arguments)
      end

      result = accept(
        IdentityProof.local(password: "new-password", password_confirmation: "new-password"),
        resolver: racing_resolver
      )

      assert_equal :cancelled, result.status
      assert_nil User.find_by(email: @invitation.email)
      assert @invitation.reload.pending?
      assert @token.reload.outstanding?
    end

    test "a lost transition reports the terminal status observed on final revalidation" do
      original = AuthenticationToken.instance_method(:transition_to!)
      AuthenticationToken.define_method(:transition_to!) { |*, **| false }
      underlying = @resolver
      token = @token
      calls = 0
      resolver = Object.new
      resolver.define_singleton_method(:revalidate) do |**arguments|
        calls += 1
        if calls == 3
          AuthenticationLinks::Resolver::Result.new(status: :cancelled, token: token)
        else
          underlying.revalidate(**arguments)
        end
      end

      result = accept(
        IdentityProof.local(password: "new-password", password_confirmation: "new-password"),
        resolver: resolver
      )

      assert_equal :cancelled, result.status
      assert_nil User.find_by(email: @invitation.email)
      assert @invitation.reload.pending?
      assert @token.reload.outstanding?
    ensure
      AuthenticationToken.define_method(:transition_to!, original) if original
    end

    test "fails closed if project ownership changes before the project lock" do
      original = AuthorityLock.method(:users!)
      project = @project
      replacement_creator_id = users(:bob).id
      AuthorityLock.define_singleton_method(:users!) do |users|
        locked = original.call(users)
        project.update_columns(user_id: replacement_creator_id)
        locked
      end

      result = accept(IdentityProof.local(password: "new-password", password_confirmation: "new-password"))

      assert_equal :invalid, result.status
      assert_nil User.find_by(email: @invitation.email)
      assert @invitation.reload.pending?
      assert @token.reload.outstanding?
      assert_equal @invitation.inviter_id, @project.reload.user_id
    ensure
      AuthorityLock.define_singleton_method(:users!, original) if original
    end

    test "fails closed if the invitation issuer changes outside the admission lock protocol" do
      original = AuthorityLock.method(:users!)
      invitation = @invitation
      replacement_inviter = users(:bob)
      AuthorityLock.define_singleton_method(:users!) do |users|
        locked = original.call(users)
        invitation.update_columns(inviter_id: replacement_inviter.id)
        locked
      end

      result = accept(IdentityProof.local(password: "new-password", password_confirmation: "new-password"))

      assert_equal :invalid, result.status
      assert_equal users(:alice).id, invitation.reload.inviter_id
      assert invitation.pending?
      assert @token.reload.outstanding?
      assert_nil User.find_by(email: invitation.email)
    ensure
      AuthorityLock.define_singleton_method(:users!, original) if original
    end

    test "fails closed when a session identity disappears from the authority lock set" do
      user = create_user(@invitation.email)
      original = AuthorityLock.method(:users!)
      AuthorityLock.define_singleton_method(:users!) do |users|
        original.call(users).reject { |candidate| candidate.id == user.id }
      end

      result = accept(IdentityProof.session(user: user))

      assert_equal :invalid_identity, result.status
      assert @invitation.reload.pending?
      assert @token.reload.outstanding?
      assert_not @project.member?(user)
    ensure
      AuthorityLock.define_singleton_method(:users!, original) if original
    end

    test "fails closed if the invitation address changes before its row lock" do
      original = AdmissionLock.method(:email!)
      invitation = @invitation
      AdmissionLock.define_singleton_method(:email!) do |email|
        normalized = original.call(email)
        invitation.update_columns(email: "racing-address@example.test")
        normalized
      end

      result = accept(IdentityProof.local(password: "new-password", password_confirmation: "new-password"))

      assert_equal :invalid, result.status
      assert_nil User.find_by(email: @invitation.email)
      assert @invitation.reload.pending?
      assert @token.reload.outstanding?
      assert_equal "newuser@example.com", @invitation.email
    ensure
      AdmissionLock.define_singleton_method(:email!, original) if original
    end

    test "fails closed if the invitation is deleted before its row lock" do
      original = AdmissionLock.method(:email!)
      invitation = @invitation
      AdmissionLock.define_singleton_method(:email!) do |email|
        normalized = original.call(email)
        invitation.destroy!
        normalized
      end

      result = accept(IdentityProof.local(password: "new-password", password_confirmation: "new-password"))

      assert_equal :invalid, result.status
      assert_nil User.find_by(email: invitation.email)
      assert ProjectInvitation.exists?(invitation.id)
      assert AuthenticationToken.exists?(@token.id)
    ensure
      AdmissionLock.define_singleton_method(:email!, original) if original
    end

    test "fails closed if the project is deleted before its row lock" do
      original = AuthorityLock.method(:users!)
      project = @project
      AuthorityLock.define_singleton_method(:users!) do |users|
        locked = original.call(users)
        project.destroy!
        locked
      end

      result = accept(IdentityProof.local(password: "new-password", password_confirmation: "new-password"))

      assert_equal :invalid, result.status
      assert_nil User.find_by(email: @invitation.email)
      assert Project.exists?(project.id)
      assert ProjectInvitation.exists?(@invitation.id)
      assert AuthenticationToken.exists?(@token.id)
    ensure
      AuthorityLock.define_singleton_method(:users!, original) if original
    end

    test "a token deleted after preflight rolls back provisional authority" do
      underlying = @resolver
      token = @token
      first_call = true
      racing_resolver = Object.new
      racing_resolver.define_singleton_method(:revalidate) do |**arguments|
        resolution = underlying.revalidate(**arguments)
        if first_call
          first_call = false
          token.delete
        end
        resolution
      end

      result = accept(
        IdentityProof.local(password: "new-password", password_confirmation: "new-password"),
        resolver: racing_resolver
      )

      assert_equal :invalid, result.status
      assert_nil User.find_by(email: @invitation.email)
      assert_not @project.project_memberships.exists?(user_id: User.where(email: @invitation.email).select(:id))
      assert @invitation.reload.pending?
    end

    test "an invitation deleted after preflight fails closed before creating authority" do
      underlying = @resolver
      invitation = @invitation
      first_call = true
      racing_resolver = Object.new
      racing_resolver.define_singleton_method(:revalidate) do |**arguments|
        resolution = underlying.revalidate(**arguments)
        if first_call
          first_call = false
          invitation.destroy!
        end
        resolution
      end

      result = accept(
        IdentityProof.local(password: "new-password", password_confirmation: "new-password"),
        resolver: racing_resolver
      )

      assert_equal :invalid, result.status
      assert_nil User.find_by(email: invitation.email)
    end

    test "database retry and persistence failures return stable non-secret results" do
      exhausted = DatabaseRetry::Exhausted.new(StandardError.new("busy"), attempts: 3)
      assert_equal :retryable_busy, accept_with_database_error(exhausted).status

      @invitation.errors.add(:email, "is unavailable")
      invalid = accept_with_database_error(ActiveRecord::RecordInvalid.new(@invitation))
      assert_equal :invalid, invalid.status
      assert_nil invalid.invitation
      assert_includes invalid.errors, "Email is unavailable"

      local_collision = accept_with_database_error(
        ActiveRecord::RecordNotUnique.new("collision"),
        proof: IdentityProof.local(password: "new-password")
      )
      assert_equal :invalid, local_collision.status

      provider_user = create_user(@invitation.email)
      provider_user.update!(oauth_provider: "google_oauth2", oauth_uid: "existing-provider")
      provider_collision = accept_with_database_error(
        ActiveRecord::RecordNotUnique.new("collision"),
        proof: google_proof(email: @invitation.email, uid: "existing-provider")
      )
      assert_equal :retryable_busy, provider_collision.status
    end

    test "a uniqueness race still returns the frozen result envelope" do
      original = DatabaseRetry.method(:call)
      DatabaseRetry.define_singleton_method(:call) { |**| raise ActiveRecord::RecordNotUnique }

      result = accept(google_proof(email: @invitation.email, uid: "racing-provider"))

      assert_instance_of Accept::Result, result
      assert_equal :identity_mismatch, result.status
    ensure
      DatabaseRetry.define_singleton_method(:call, original)
    end

    private

    def accept(proof, resolver: @resolver, clock: -> { NOW })
      Accept.call(
        token_id: @token.id,
        proof: proof,
        resolver: resolver,
        deployment: Deployment.new(billing?: false),
        clock: clock
      )
    end

    def issue_token(invitation)
      issued = nil
      ProjectInvitation.transaction do
        locked = ProjectInvitation.lock.find(invitation.id)
        issued = @issuer.call(purpose: :invitation, subject: locked, expires_at: NOW + 7.days)
      end
      issued
    end

    def create_user(email)
      User.create!(email: email, password: "password123", confirmed_at: Time.current)
    end

    def google_proof(email:, uid:)
      IdentityProof.provider(
        "provider" => "google_oauth2",
        "uid" => uid,
        "info" => { "email" => email, "email_verified" => true }
      )
    end

    def reset_grant(state)
      now = NOW + 1.second
      AuthenticationToken.where(id: @token.id).update_all(
        state: AuthenticationToken.states.fetch(state),
        terminal_at: state == :outstanding ? nil : now,
        updated_at: now
      )
      @token.reload
    end

    def accept_with_database_error(error, proof: IdentityProof.local(password: "new-password"))
      original = DatabaseRetry.method(:call)
      DatabaseRetry.define_singleton_method(:call) { |**| raise error }
      accept(proof)
    ensure
      DatabaseRetry.define_singleton_method(:call, original)
    end
  end
end
