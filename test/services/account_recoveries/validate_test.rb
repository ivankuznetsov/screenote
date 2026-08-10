# frozen_string_literal: true

require "test_helper"
require_relative "../../support/instance_administration_test_helper"

module AccountRecoveries
  class ValidateTest < ActiveSupport::TestCase
    include InstanceAdministrationTestHelper
    self.use_transactional_tests = false

    Resolution = Data.define(:status, :token) do
      def valid?
        status == :valid
      end
    end

    class SequenceResolver
      def initialize(*resolutions)
        @resolutions = resolutions
      end

      def revalidate(**)
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

    test "validates an outstanding issuer-bound recovery token without mutating it" do
      before = @issued.token.attributes

      result = Validate.call(token_id: @issued.token.id)

      assert_equal :valid, result.status
      assert_equal @target, result.user
      assert_equal @issued.token, result.token
      assert_equal before, @issued.token.reload.attributes
    end

    test "rejects invalid identifiers before consulting the resolver" do
      resolver = SequenceResolver.new

      [ nil, "1", 0, -1 ].each do |token_id|
        assert_equal :invalid, Validate.call(token_id: token_id, resolver: resolver).status
      end
    end

    test "preserves terminal statuses and collapses unknown resolver failures to invalid" do
      %i[expired already_used superseded cancelled].each do |status|
        resolver = SequenceResolver.new(Resolution.new(status: status, token: @issued.token))
        assert_equal status, Validate.call(token_id: @issued.token.id, resolver: resolver).status
      end

      resolver = SequenceResolver.new(Resolution.new(status: :unavailable, token: @issued.token))
      assert_equal :invalid, Validate.call(token_id: @issued.token.id, resolver: resolver).status
    end

    test "fails closed when the installation or locked token disappears" do
      hint = @issued.token
      resolver = SequenceResolver.new(Resolution.new(status: :valid, token: hint))
      Installation.delete_all

      assert_equal :unavailable, Validate.call(token_id: hint.id, resolver: resolver).status

      prepare_claimed_installation(administrator: @administrator)
      token_id = hint.id
      hint.destroy!
      resolver = SequenceResolver.new(Resolution.new(status: :valid, token: hint))

      assert_equal :invalid, Validate.call(token_id: token_id, resolver: resolver).status
    end

    test "rejects an unclaimed installation after taking the authority locks" do
      Installation.current.update_columns(
        state: "unclaimed",
        administrator_id: nil,
        claimed_at: nil
      )
      resolver = SequenceResolver.new(
        Resolution.new(status: :valid, token: @issued.token),
        Resolution.new(status: :valid, token: @issued.token)
      )

      assert_equal :unavailable, Validate.call(token_id: @issued.token.id, resolver: resolver).status
    end

    test "rejects missing issuer and target records from a stale preflight hint" do
      missing_issuer = token_hint(issued_by_user_id: 2_147_483_647)
      issuer_resolver = SequenceResolver.new(
        Resolution.new(status: :valid, token: missing_issuer),
        Resolution.new(status: :valid, token: @issued.token)
      )
      assert_equal :issuer_revoked,
        Validate.call(token_id: @issued.token.id, resolver: issuer_resolver).status

      missing_target = token_hint(user_id: 2_147_483_647)
      target_resolver = SequenceResolver.new(
        Resolution.new(status: :valid, token: missing_target),
        Resolution.new(status: :valid, token: @issued.token)
      )
      assert_equal :inactive_target,
        Validate.call(token_id: @issued.token.id, resolver: target_resolver).status
    end

    test "revalidates under lock and rejects a stale subject binding" do
      stale_subject = token_hint(user_id: @administrator.id)
      mismatch_resolver = SequenceResolver.new(
        Resolution.new(status: :valid, token: stale_subject),
        Resolution.new(status: :valid, token: @issued.token)
      )
      assert_equal :invalid,
        Validate.call(token_id: @issued.token.id, resolver: mismatch_resolver).status

      expired_resolver = SequenceResolver.new(
        Resolution.new(status: :valid, token: @issued.token),
        Resolution.new(status: :expired, token: @issued.token)
      )
      assert_equal :expired,
        Validate.call(token_id: @issued.token.id, resolver: expired_resolver).status
    end

    test "maps exhausted contention and database failures to stable statuses" do
      busy = lambda do |*|
        raise DatabaseRetry::Exhausted.new(ActiveRecord::Deadlocked.new, attempts: 3)
      end
      with_singleton_method_stub(DatabaseRetry, :call, busy) do
        assert_equal :retryable_busy, Validate.call(token_id: @issued.token.id).status
      end

      unavailable = ->(*) { raise ActiveRecord::StatementInvalid, "database unavailable" }
      with_singleton_method_stub(DatabaseRetry, :call, unavailable) do
        assert_equal :unavailable, Validate.call(token_id: @issued.token.id).status
      end
    end

    private

    def token_hint(user_id: @issued.token.user_id, issued_by_user_id: @issued.token.issued_by_user_id)
      @issued.token.dup.tap do |hint|
        hint.id = @issued.token.id
        hint.user_id = user_id
        hint.issued_by_user_id = issued_by_user_id
      end
    end
  end
end
