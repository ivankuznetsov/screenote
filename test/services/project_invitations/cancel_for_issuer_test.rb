# frozen_string_literal: true

require "test_helper"

module ProjectInvitations
  class CancelForIssuerTest < ActiveSupport::TestCase
    self.use_transactional_tests = false

    SECRET = "cancel-for-invitation-issuer-test-secret-0123456"
    NOW = Time.utc(2026, 8, 5, 12)

    setup do
      @issuer_user = users(:alice)
      @project = projects(:alice_project)
      @invitation = project_invitations(:pending_invitation)
      keyring = AuthenticationLinks::Keyring.new(secret_key_base: SECRET)
      issuer = AuthenticationLinks::Issuer.new(
        origin: "https://screenote.example.test",
        keyring: keyring,
        clock: -> { NOW }
      )
      ProjectInvitation.transaction do
        locked = ProjectInvitation.lock.find(@invitation.id)
        @token = issuer.call(
          purpose: :invitation,
          subject: locked,
          expires_at: NOW + 7.days
        ).token
      end
    end

    teardown do
      AuthenticationToken.delete_all
    end

    test "requires the caller's transaction and a prelocked invitation scope" do
      assert_raises(CancelForIssuer::OutsideTransaction) do
        CancelForIssuer.lock_scope!(issuer: @issuer_user, projects: [ @project ])
      end
      assert_raises(CancelForIssuer::OutsideTransaction) do
        CancelForIssuer.call(issuer: @issuer_user, scope: nil, clock: -> { NOW })
      end


      User.transaction do
        assert_raises(CancelForIssuer::InvalidScope) do
          CancelForIssuer.lock_scope!(issuer: nil, projects: [ @project ])
        end
        assert_raises(CancelForIssuer::InvalidScope) do
          CancelForIssuer.lock_scope!(issuer: User.new, projects: [ @project ])
        end
        assert_raises(CancelForIssuer::InvalidScope) do
          CancelForIssuer.lock_scope!(issuer: @issuer_user, projects: [ Project.new ])
        end

        locked_issuer = AuthorityLock.user!(@issuer_user)
        wrong_scope = CancelForIssuer::LockScope.new(
          issuer_id: users(:bob).id,
          project_ids: [ @project.id ].freeze,
          invitations: [ @invitation ].freeze
        )
        assert_raises(CancelForIssuer::InvalidScope) do
          CancelForIssuer.call(issuer: locked_issuer, scope: wrong_scope, clock: -> { NOW })
        end
        assert_raises(CancelForIssuer::InvalidScope) do
          CancelForIssuer.call(issuer: locked_issuer, scope: Object.new, clock: -> { NOW })
        end
        assert_raises(CancelForIssuer::InvalidScope) do
          CancelForIssuer.call(issuer: nil, scope: wrong_scope, clock: -> { NOW })
        end
      end
    end

    test "locks invitations before the caller's membership phase and terminalizes tokens last" do
      statements = []
      result = nil
      subscriber = lambda do |_name, _started, _finished, _unique_id, payload|
        statements << payload.fetch(:sql)
      end

      ActiveSupport::Notifications.subscribed(subscriber, "sql.active_record") do
        User.transaction do
          locked_issuer = AuthorityLock.user!(@issuer_user)
          locked_project = Project.lock.find(@project.id)
          scope = CancelForIssuer.lock_scope!(issuer: locked_issuer, projects: [ locked_project ])
          ProjectMembership.where(project_id: @project.id).order(:id).lock.load
          result = CancelForIssuer.call(issuer: locked_issuer, scope: scope, clock: -> { NOW })
        end
      end

      invitation_lock = statements.index { |sql| sql.include?("project_invitations") }
      membership_lock = statements.index { |sql| sql.include?("project_memberships") }
      token_lock = statements.index { |sql| sql.include?("authentication_tokens") }

      assert_equal :cancelled, result.status
      assert invitation_lock < membership_lock
      assert membership_lock < token_lock
      assert @invitation.reload.cancelled?
      assert @token.reload.cancelled?
    end

    test "returns none for an empty locked scope" do
      result = nil
      User.transaction do
        locked_issuer = AuthorityLock.user!(@issuer_user)
        other_project = Project.lock.find(projects(:alice_second_project).id)
        scope = CancelForIssuer.lock_scope!(issuer: locked_issuer, projects: [ other_project ])
        ProjectMembership.where(project_id: other_project.id).order(:id).lock.load
        result = CancelForIssuer.call(issuer: locked_issuer, scope: scope, clock: -> { NOW })
      end

      assert_equal :none, result.status
      assert @invitation.reload.pending?
      assert @token.reload.outstanding?
    end

    test "filters stale scope entries and leaves their rows untouched" do
      result = nil
      User.transaction do
        locked_issuer = AuthorityLock.user!(@issuer_user)
        stale_invitation = ProjectInvitation.find(@invitation.id)
        stale_invitation.status = :accepted
        scope = CancelForIssuer::LockScope.new(
          issuer_id: locked_issuer.id,
          project_ids: [ @project.id ].freeze,
          invitations: [ stale_invitation ].freeze
        )
        result = CancelForIssuer.call(issuer: locked_issuer, scope: scope, clock: -> { NOW })
      end

      assert_equal :none, result.status
      assert_empty result.invitations
      assert @invitation.reload.pending?
      assert @token.reload.outstanding?
    end

    test "fails closed for every forged entry in an otherwise valid scope" do
      result = nil
      User.transaction do
        locked_issuer = AuthorityLock.user!(@issuer_user)
        unpersisted = @invitation.dup
        accepted = ProjectInvitation.find(@invitation.id)
        accepted.status = :accepted
        wrong_issuer = ProjectInvitation.find(@invitation.id)
        wrong_issuer.inviter_id = users(:bob).id
        outside_project = ProjectInvitation.find(@invitation.id)
        outside_project.project_id = projects(:alice_second_project).id
        scope = CancelForIssuer::LockScope.new(
          issuer_id: locked_issuer.id,
          project_ids: [ @project.id ].freeze,
          invitations: [ unpersisted, accepted, wrong_issuer, outside_project ].freeze
        )

        result = CancelForIssuer.call(issuer: locked_issuer, scope: scope, clock: -> { NOW })
      end

      assert_equal :none, result.status
      assert_empty result.invitations
      assert @invitation.reload.pending?
      assert @token.reload.outstanding?
    end

    test "cancelling an invitation preserves a token already consumed by a racing actor" do
      @token.update_columns(
        state: AuthenticationToken.states.fetch(:consumed),
        terminal_at: NOW
      )

      result = nil
      User.transaction do
        locked_issuer = AuthorityLock.user!(@issuer_user)
        locked_project = Project.lock.find(@project.id)
        scope = CancelForIssuer.lock_scope!(issuer: locked_issuer, projects: [ locked_project ])
        ProjectMembership.where(project_id: @project.id).order(:id).lock.load
        result = CancelForIssuer.call(issuer: locked_issuer, scope: scope, clock: -> { NOW })
      end

      assert_equal :cancelled, result.status
      assert @invitation.reload.cancelled?
      assert @token.reload.consumed?
    end
  end
end
