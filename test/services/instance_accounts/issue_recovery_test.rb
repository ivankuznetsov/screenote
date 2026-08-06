# frozen_string_literal: true

require "test_helper"
require_relative "../../support/instance_administration_test_helper"

module InstanceAccounts
  class IssueRecoveryTest < ActiveSupport::TestCase
    include InstanceAdministrationTestHelper
    self.use_transactional_tests = false

    setup do
      @administrator = users(:alice)
      @target = users(:bob)
      prepare_claimed_installation(administrator: @administrator)
      @target.update!(access_status: :active)
    end

    teardown do
      AuthenticationToken.delete_all
      InstallationAuditEvent.delete_all
      Installation.delete_all
    end

    test "issues one digest-only fifteen minute recovery credential" do
      now = Time.utc(2026, 8, 5, 12, 0, 0)

      result = IssueRecovery.call(
        actor: @administrator,
        target: @target,
        clock: -> { now }
      )

      assert_equal :issued, result.status
      assert_equal now + 15.minutes, result.expires_at
      assert_equal @administrator, result.token.issued_by_user
      assert_equal @target, result.token.user
      assert result.token.account_recovery?
      assert result.token.outstanding?
      assert_not_includes result.token.attributes.to_json, result.presentation.fragment
      assert_not_includes InstallationAuditEvent.order(:id).last.attributes.to_json, result.presentation.fragment
      assert_equal "account_recovery_issued", InstallationAuditEvent.order(:id).last.event_type
      assert_match "[FILTERED]", result.inspect
      assert_not_includes result.inspect, result.presentation.fragment
      assert_not_includes result.as_json.to_json, result.presentation.fragment
    end

    test "reissuing supersedes the prior credential" do
      first = IssueRecovery.call(actor: @administrator, target: @target)
      second = IssueRecovery.call(actor: @administrator, target: @target)

      assert_equal :issued, second.status
      assert first.token.reload.superseded?
      assert second.token.reload.outstanding?
      assert_operator second.token.generation, :>, first.token.generation
    end

    test "does not issue recovery for a suspended account" do
      @target.update!(access_status: :suspended)

      assert_no_difference "AuthenticationToken.count" do
        result = IssueRecovery.call(actor: @administrator, target: @target)
        assert_equal :inactive_target, result.status
      end
    end

    test "fails closed when instance authority is unavailable or the actor is forbidden" do
      Installation.delete_all
      assert_no_difference "AuthenticationToken.count" do
        assert_equal :unavailable,
          IssueRecovery.call(actor: @administrator, target: @target).status
      end

      prepare_claimed_installation(administrator: @administrator)
      assert_difference "InstallationAuditEvent.count", 1 do
        assert_no_difference "AuthenticationToken.count" do
          result = IssueRecovery.call(actor: @target, target: @target)
          assert_equal :forbidden, result.status
        end
      end
      denial = InstallationAuditEvent.order(:id).last
      assert_equal "instance_action_denied", denial.event_type
      assert_equal "forbidden", denial.metadata.fetch("reason")
    end

    test "returns not found without audit leakage for a missing operator target" do
      assert_no_difference "AuthenticationToken.count" do
        assert_difference "InstallationAuditEvent.count", 1 do
          result = IssueRecovery.call(actor: @administrator, target: nil)
          assert_equal :not_found, result.status
        end
      end

      assert_no_difference "InstallationAuditEvent.count" do
        result = IssueRecovery.call(actor: nil, target: nil, operator: true, channel: "local_operator")
        assert_equal :not_found, result.status
      end
    end

    test "operator recovery is restricted to the current administrator" do
      denied = IssueRecovery.call(
        actor: nil,
        target: @target,
        operator: true,
        channel: "local_operator"
      )

      assert_equal :stale_administrator, denied.status
      assert_difference "AuthenticationToken.account_recovery.count", 1 do
        issued = IssueRecovery.call(
          actor: nil,
          target: @administrator,
          operator: true,
          channel: "local_operator"
        )
        assert_equal :issued, issued.status
      end
    end

    test "purges only terminal recovery metadata older than twenty four hours" do
      now = Time.utc(2026, 8, 5, 12, 0, 0)
      old = create_recovery_token(
        subject: @target,
        issuer: @administrator,
        now: now - 25.hours,
        expires_at: now - 24.hours - 45.minutes
      )
      old.token.transition_to!(:cancelled, at: now - 24.hours - 44.minutes)
      boundary = create_recovery_token(
        subject: @target,
        issuer: @administrator,
        now: now - 24.hours,
        expires_at: now - 23.hours - 45.minutes
      )
      boundary.token.transition_to!(:cancelled, at: now - 24.hours)

      issued = IssueRecovery.call(
        actor: @administrator,
        target: @target,
        clock: -> { now }
      )

      assert_equal :issued, issued.status
      assert_not AuthenticationToken.exists?(old.token.id)
      assert AuthenticationToken.exists?(boundary.token.id)
      assert issued.token.reload.outstanding?
    end

    test "maps retry exhaustion and issuer persistence failures to stable statuses" do
      busy = lambda do |*|
        raise DatabaseRetry::Exhausted.new(ActiveRecord::Deadlocked.new, attempts: 3)
      end
      with_singleton_method_stub(DatabaseRetry, :call, busy) do
        assert_equal :retryable_busy,
          IssueRecovery.call(actor: @administrator, target: @target).status
      end

      invalid_issuer = Object.new
      invalid_issuer.define_singleton_method(:call) do |**|
        raise AuthenticationLinks::Issuer::InvalidExpiry, "invalid expiry"
      end
      result = IssueRecovery.call(
        actor: @administrator,
        target: @target,
        authentication_link_issuer: invalid_issuer
      )
      assert_equal :unavailable, result.status

      unavailable_issuer = Object.new
      unavailable_issuer.define_singleton_method(:call) do |**|
        raise ActiveRecord::StatementInvalid, "database unavailable"
      end
      result = IssueRecovery.call(
        actor: @administrator,
        target: @target,
        authentication_link_issuer: unavailable_issuer
      )
      assert_equal :unavailable, result.status
    end

    test "direct construction uses the default clock and serializes present identifiers" do
      now = Time.utc(2026, 8, 5, 12, 0, 0)

      travel_to now do
        operation = IssueRecovery.new(actor: @administrator, target: @target)
        result = operation.call

        assert_equal :issued, result.status
        assert_equal now + 15.minutes, result.expires_at
        assert_match(/actor_id=#{@administrator.id}/, operation.inspect)
        assert_match(/target_id=#{@target.id}/, operation.to_s)
        assert_equal @administrator.id, operation.as_json.fetch("actor_id")
        assert_equal @target.id, operation.as_json.fetch("target_id")
      end
    end

    test "operation serialization tolerates missing actors and targets without exposing secrets" do
      operation = IssueRecovery.new(actor: nil, target: nil)

      assert_match "actor_id=nil", operation.inspect
      assert_match "target_id=nil", operation.inspect
      assert_includes operation.inspect, "FILTERED"
      assert_nil operation.as_json.fetch("actor_id")
      assert_nil operation.as_json.fetch("target_id")
    end
  end
end
