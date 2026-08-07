# frozen_string_literal: true

require "test_helper"
require_relative "../../support/instance_administration_test_helper"

module InstanceAccounts
  class ListTest < ActiveSupport::TestCase
    include InstanceAdministrationTestHelper
    self.use_transactional_tests = false

    setup do
      @administrator = users(:alice)
      @target = users(:bob)
      prepare_claimed_installation(administrator: @administrator)
      @target.update!(access_status: :suspended)
    end

    teardown do
      InstallationAuditEvent.delete_all
      Installation.delete_all
    end

    test "lists only bounded account fields and marks active state and administrator authority" do
      result = List.call(actor: @administrator)

      assert_predicate result, :success?
      administrator = result.accounts.find { |account| account.id == @administrator.id }
      target = result.accounts.find { |account| account.id == @target.id }
      assert administrator.active?
      assert administrator.administrator
      assert target.suspended?
      assert_not target.administrator
      assert_equal @administrator.id, result.administrator_id
      assert_predicate result.accounts, :frozen?
    end

    test "fails closed when installation authority is unavailable" do
      Installation.delete_all

      result = List.call(actor: @administrator)

      assert_equal :unavailable, result.status
      assert_empty result.accounts
      assert_nil result.administrator_id
    end

    test "audits an authenticated non-administrator denial" do
      assert_difference "InstallationAuditEvent.count", 1 do
        result = List.call(actor: @target)
        assert_equal :forbidden, result.status
      end

      event = InstallationAuditEvent.order(:id).last
      assert_equal "instance_action_denied", event.event_type
      assert_equal "list_accounts", event.metadata.fetch("action")
    end

    test "maps retry exhaustion and database failures to stable statuses" do
      exhausted = DatabaseRetry::Exhausted.new(ActiveRecord::Deadlocked.new, attempts: 3)
      with_singleton_method_stub(DatabaseRetry, :call, ->(*) { raise exhausted }) do
        assert_equal :retryable_busy, List.call(actor: @administrator).status
      end
      with_singleton_method_stub(
        DatabaseRetry,
        :call,
        ->(*) { raise ActiveRecord::StatementInvalid, "database unavailable" }
      ) do
        assert_equal :unavailable, List.call(actor: @administrator).status
      end
    end
  end
end
