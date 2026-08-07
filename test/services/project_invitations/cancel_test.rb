# frozen_string_literal: true

require "test_helper"

module ProjectInvitations
  class CancelTest < ActiveSupport::TestCase
    self.use_transactional_tests = false

    SECRET = "project-invitation-cancel-test-secret-01234567"
    NOW = Time.utc(2026, 8, 5, 12)

    setup do
      @invitation = project_invitations(:pending_invitation)
      @project = @invitation.project
      @owner = @invitation.inviter
      @principal = AuthenticatedPrincipal.for_user(@owner)
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

    test "cancels a pending invitation and token without deleting either row" do
      assert_no_difference [ "ProjectInvitation.count", "AuthenticationToken.count" ] do
        result = cancel
        assert_equal :cancelled, result.status
        assert_predicate result, :success?
        assert_equal @invitation, result.invitation
      end

      assert @invitation.reload.cancelled?
      assert @token.reload.cancelled?
    end

    test "returns stable terminal authorization and lookup statuses" do
      assert_equal :cancelled, cancel.status
      assert_equal :already_cancelled, cancel.status

      @invitation.update!(status: :accepted)
      assert_equal :already_accepted, cancel.status

      forbidden = Cancel.call(
        principal: AuthenticatedPrincipal.for_user(users(:bob)),
        project: @project,
        invitation_id: @invitation.id,
        clock: -> { NOW }
      )
      assert_equal :forbidden, forbidden.status

      missing = Cancel.call(
        principal: @principal,
        project: @project,
        invitation_id: -1,
        clock: -> { NOW }
      )
      assert_equal :not_found, missing.status

      absent = Cancel.call(
        principal: @principal,
        project: @project,
        invitation_id: @invitation.id + 10_000,
        clock: -> { NOW }
      )
      assert_equal :not_found, absent.status

      no_project = Cancel.call(
        principal: @principal,
        project: nil,
        invitation_id: @invitation.id,
        clock: -> { NOW }
      )
      assert_equal :not_found, no_project.status

      no_principal = Cancel.call(
        principal: nil,
        project: @project,
        invitation_id: @invitation.id,
        clock: -> { NOW }
      )
      assert_equal :forbidden, no_principal.status

      malformed = Cancel.call(
        principal: @principal,
        project: @project,
        invitation_id: "#{@invitation.id}junk",
        clock: -> { NOW }
      )
      assert_equal :not_found, malformed.status
      assert_not_predicate malformed, :success?
      assert @invitation.reload.accepted?
    end

    test "terminal invitation races terminalize an outstanding token consistently" do
      @invitation.update_columns(status: ProjectInvitation.statuses.fetch(:accepted))
      accepted = cancel
      assert_equal :already_accepted, accepted.status
      assert @token.reload.consumed?

      @invitation.update_columns(status: ProjectInvitation.statuses.fetch(:cancelled))
      @token.update_columns(
        state: AuthenticationToken.states.fetch(:outstanding),
        terminal_at: nil
      )
      cancelled = cancel
      assert_equal :already_cancelled, cancelled.status
      assert @token.reload.cancelled?
    end

    test "cancelling a pending invitation preserves a token consumed by a racing accept" do
      @token.update_columns(
        state: AuthenticationToken.states.fetch(:consumed),
        terminal_at: NOW
      )

      result = cancel

      assert_equal :cancelled, result.status
      assert @invitation.reload.cancelled?
      assert @token.reload.consumed?
    end

    test "fails closed if the project creator changes before the project lock" do
      original = AuthorityLock.method(:users!)
      project = @project
      replacement_creator_id = users(:bob).id
      AuthorityLock.define_singleton_method(:users!) do |users|
        locked = original.call(users)
        project.update_columns(user_id: replacement_creator_id)
        locked
      end

      result = cancel

      assert_equal :not_found, result.status
      assert @invitation.reload.pending?
      assert @token.reload.outstanding?
    ensure
      AuthorityLock.define_singleton_method(:users!, original) if original
      project&.update_columns(user_id: @owner.id)
    end

    test "fails closed if the invitation identity changes before its row lock" do
      original = AdmissionLock.method(:email!)
      invitation = @invitation
      AdmissionLock.define_singleton_method(:email!) do |email|
        normalized = original.call(email)
        invitation.update_columns(email: "racing-address@example.test")
        normalized
      end

      result = cancel

      assert_equal :not_found, result.status
      assert @invitation.reload.pending?
      assert @token.reload.outstanding?
    ensure
      AdmissionLock.define_singleton_method(:email!, original) if original
      invitation&.update_columns(email: "newuser@example.com")
    end

    test "fails closed if the invitation is deleted before its row lock" do
      original = AdmissionLock.method(:email!)
      invitation = @invitation
      AdmissionLock.define_singleton_method(:email!) do |email|
        normalized = original.call(email)
        invitation.destroy!
        normalized
      end

      result = cancel

      assert_equal :not_found, result.status
      assert_not ProjectInvitation.exists?(invitation.id)
      assert_not AuthenticationToken.exists?(@token.id)
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

      result = cancel

      assert_equal :not_found, result.status
      assert_not Project.exists?(project.id)
      assert_not ProjectInvitation.exists?(@invitation.id)
      assert_not AuthenticationToken.exists?(@token.id)
    ensure
      AuthorityLock.define_singleton_method(:users!, original) if original
    end

    test "rejects inactive project and read-only principals" do
      api_principal = AuthenticatedPrincipal.for_api_key(api_keys(:alice_key))
      api_result = Cancel.call(
        principal: api_principal,
        project: @project,
        invitation_id: @invitation.id,
        clock: -> { NOW }
      )
      assert_equal :forbidden, api_result.status

      read_only = AuthenticatedPrincipal.new(
        kind: :user,
        user: @owner,
        issuer: @owner,
        scopes: [ AuthenticatedPrincipal::READ_SCOPE ]
      )
      read_only_result = Cancel.call(
        principal: read_only,
        project: @project,
        invitation_id: @invitation.id,
        clock: -> { NOW }
      )
      assert_equal :forbidden, read_only_result.status

      @owner.update!(access_status: :suspended)
      assert_equal :forbidden, cancel.status
      assert @invitation.reload.pending?
      assert @token.reload.outstanding?
    end

    test "database exhaustion returns retryable busy without cancelling" do
      original = DatabaseRetry.method(:call)
      error = DatabaseRetry::Exhausted.new(StandardError.new("busy"), attempts: 3)
      DatabaseRetry.define_singleton_method(:call) { |**| raise error }

      result = cancel

      assert_equal :retryable_busy, result.status
      assert @invitation.reload.pending?
      assert @token.reload.outstanding?
    ensure
      DatabaseRetry.define_singleton_method(:call, original) if original
    end

    private

    def cancel
      Cancel.call(
        principal: @principal,
        project: @project,
        invitation_id: @invitation.id,
        clock: -> { NOW }
      )
    end
  end
end
