# frozen_string_literal: true

require "test_helper"
require_relative "../../support/instance_administration_test_helper"

module AccountRecoveries
  class ConsumeTest < ActiveSupport::TestCase
    include InstanceAdministrationTestHelper
    self.use_transactional_tests = false

    Resolution = Data.define(:status, :token) do
      def valid?
        status == :valid
      end
    end

    class SequenceResolver
      def initialize(*resolutions, before_revalidation: {})
        @resolutions = resolutions
        @before_revalidation = before_revalidation
        @calls = 0
      end

      def revalidate(**)
        @calls += 1
        @before_revalidation[@calls]&.call
        @resolutions.shift || raise("unexpected recovery-token revalidation")
      end
    end

    setup do
      @administrator = users(:alice)
      @target = users(:bob)
      prepare_claimed_installation(administrator: @administrator)
      @target.update!(access_status: :active)
      @issued = create_recovery_token(subject: @target, issuer: @administrator)
    end

    teardown do
      AuthenticationToken.delete_all
      InstallationAuditEvent.delete_all
      Installation.delete_all
    end

    test "consumes once, changes only the local password, and revokes old credentials" do
      old_session_id = @target.sessions.first!.id

      result = Consume.call(
        token_id: @issued.token.id,
        password: "new correct horse battery staple",
        password_confirmation: "new correct horse battery staple"
      )

      assert_equal :recovered, result.status
      assert_equal @target, result.user
      assert @target.reload.authenticate("new correct horse battery staple")
      assert @issued.token.reload.consumed?
      assert_not Session.exists?(old_session_id)
      assert api_keys(:bob_key).reload.revoked?
      assert_equal "account_recovered", InstallationAuditEvent.order(:id).last.event_type

      replay = Consume.call(
        token_id: @issued.token.id,
        password: "another password",
        password_confirmation: "another password"
      )
      assert_equal :already_used, replay.status
      assert_not @target.reload.authenticate("another password")
    end

    test "is invalid for a suspended subject or stale administrator issuer" do
      @target.update!(access_status: :suspended)
      result = Consume.call(
        token_id: @issued.token.id,
        password: "new correct horse battery staple",
        password_confirmation: "new correct horse battery staple"
      )
      assert_equal :inactive_target, result.status

      @target.update!(access_status: :active)
      @installation = Installation.current
      @installation.update!(administrator: users(:admin))
      stale = Consume.call(
        token_id: @issued.token.id,
        password: "new correct horse battery staple",
        password_confirmation: "new correct horse battery staple"
      )
      assert_equal :issuer_revoked, stale.status
    end

    test "expires exactly at the fifteen minute boundary" do
      issued_at = Time.utc(2026, 8, 5, 12, 0, 0)
      issued = create_recovery_token(
        subject: users(:admin),
        issuer: @administrator,
        now: issued_at,
        expires_at: issued_at + 15.minutes
      )

      result = Consume.call(
        token_id: issued.token.id,
        password: "new correct horse battery staple",
        password_confirmation: "new correct horse battery staple",
        clock: -> { issued_at + 15.minutes }
      )

      assert_equal :expired, result.status
    end

    test "rejects invalid identifiers and resolver failures before changing the password" do
      resolver = SequenceResolver.new
      [ nil, "1", 0, -1 ].each do |token_id|
        result = Consume.call(
          token_id: token_id,
          password: "new correct horse battery staple",
          password_confirmation: "new correct horse battery staple",
          resolver: resolver
        )
        assert_equal :invalid, result.status
      end

      %i[expired already_used superseded cancelled].each do |status|
        status_resolver = SequenceResolver.new(Resolution.new(status: status, token: @issued.token))
        result = consume_with(resolver: status_resolver)
        assert_equal status, result.status
      end

      unknown = SequenceResolver.new(Resolution.new(status: :unavailable, token: @issued.token))
      assert_equal :invalid, consume_with(resolver: unknown).status
      assert_not @target.reload.authenticate("new correct horse battery staple")
    end

    test "returns validation errors without consuming the token or changing the password" do
      result = Consume.call(
        token_id: @issued.token.id,
        password: "new password",
        password_confirmation: "different password"
      )

      assert_equal :invalid, result.status
      assert_includes result.errors.keys, :password_confirmation
      assert @issued.token.reload.outstanding?
      assert_not @target.reload.authenticate("new password")
    end

    test "fails closed when the installation or locked token disappears" do
      hint = @issued.token
      resolver = SequenceResolver.new(Resolution.new(status: :valid, token: hint))
      Installation.delete_all

      assert_equal :unavailable, consume_with(resolver: resolver).status

      prepare_claimed_installation(administrator: @administrator)
      hint.destroy!
      resolver = SequenceResolver.new(Resolution.new(status: :valid, token: hint))

      assert_equal :invalid, consume_with(resolver: resolver).status
      assert_not @target.reload.authenticate("new correct horse battery staple")
    end

    test "rejects an unclaimed installation after taking the authority locks" do
      Installation.current.update_columns(
        state: "unclaimed",
        administrator_id: nil,
        claimed_at: nil
      )
      resolver = SequenceResolver.new(Resolution.new(status: :valid, token: @issued.token))

      assert_equal :unavailable, consume_with(resolver: resolver).status
    end

    test "rejects missing issuer and target records from a stale preflight hint" do
      missing_issuer = token_hint(issued_by_user_id: 2_147_483_647)
      issuer_resolver = SequenceResolver.new(Resolution.new(status: :valid, token: missing_issuer))
      assert_equal :issuer_revoked, consume_with(resolver: issuer_resolver).status

      missing_target = token_hint(user_id: 2_147_483_647)
      target_resolver = SequenceResolver.new(Resolution.new(status: :valid, token: missing_target))
      assert_equal :inactive_target, consume_with(resolver: target_resolver).status
    end

    test "revalidates under lock and rejects stale token bindings" do
      stale_subject = token_hint(user_id: @administrator.id)
      mismatch_resolver = SequenceResolver.new(
        Resolution.new(status: :valid, token: stale_subject),
        Resolution.new(status: :valid, token: @issued.token)
      )
      assert_equal :invalid, consume_with(resolver: mismatch_resolver).status

      expired_resolver = SequenceResolver.new(
        Resolution.new(status: :valid, token: @issued.token),
        Resolution.new(status: :expired, token: @issued.token)
      )
      assert_equal :expired, consume_with(resolver: expired_resolver).status
      assert @issued.token.reload.outstanding?
    end

    test "a lost consume race leaves the password and existing credentials unchanged" do
      old_session_id = @target.sessions.first!.id
      bob_key = api_keys(:bob_key)
      transition_elsewhere = lambda do
        now = Time.current
        AuthenticationToken.where(id: @issued.token.id).update_all(
          state: AuthenticationToken.states.fetch(:consumed),
          terminal_at: now,
          updated_at: now
        )
      end
      resolver = SequenceResolver.new(
        Resolution.new(status: :valid, token: @issued.token),
        Resolution.new(status: :valid, token: @issued.token),
        before_revalidation: { 2 => transition_elsewhere }
      )

      assert_no_difference "InstallationAuditEvent.count" do
        result = consume_with(resolver: resolver)
        assert_equal :already_used, result.status
      end

      assert @issued.token.reload.consumed?
      assert @target.reload.authenticate("password123")
      assert_not @target.authenticate("new correct horse battery staple")
      assert Session.exists?(old_session_id)
      assert_not bob_key.reload.revoked?
    end

    test "maps retry exhaustion record validation and database failures to stable results" do
      busy = lambda do |*|
        raise DatabaseRetry::Exhausted.new(ActiveRecord::Deadlocked.new, attempts: 3)
      end
      with_singleton_method_stub(DatabaseRetry, :call, busy) do
        assert_equal :retryable_busy, consume_with.status
      end

      invalid_record = @target
      invalid_record.errors.add(:password, "is unavailable")
      invalid = ->(*) { raise ActiveRecord::RecordInvalid.new(invalid_record) }
      with_singleton_method_stub(InstanceAccounts::CredentialRevoker, :revoke!, invalid) do
        result = consume_with
        assert_equal :invalid, result.status
        assert_includes result.errors.fetch(:password), "is unavailable"
      end

      unavailable = ->(*) { raise ActiveRecord::StatementInvalid, "database unavailable" }
      with_singleton_method_stub(InstanceAccounts::CredentialRevoker, :revoke!, unavailable) do
        assert_equal :unavailable, consume_with.status
      end
      assert @issued.token.reload.outstanding?
    end

    test "result and operation inspection never expose submitted passwords" do
      password = "unloggable recovery password"
      operation = Consume.new(
        token_id: @issued.token.id,
        password: password,
        password_confirmation: password
      )

      assert_not_includes operation.inspect, password
      assert_not_includes operation.to_s, password
      assert_not_includes operation.as_json.to_json, password

      result = operation.call
      assert_not_includes result.inspect, password
      assert_not_includes result.as_json.to_json, password
    end

    private

    def consume_with(resolver: nil)
      Consume.call(
        token_id: @issued.token.id,
        password: "new correct horse battery staple",
        password_confirmation: "new correct horse battery staple",
        resolver: resolver
      )
    end

    def token_hint(user_id: @issued.token.user_id, issued_by_user_id: @issued.token.issued_by_user_id)
      @issued.token.dup.tap do |hint|
        hint.id = @issued.token.id
        hint.user_id = user_id
        hint.issued_by_user_id = issued_by_user_id
      end
    end
  end
end
