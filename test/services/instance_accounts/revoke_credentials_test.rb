# frozen_string_literal: true

require "test_helper"
require_relative "../../support/instance_administration_test_helper"

module InstanceAccounts
  class RevokeCredentialsTest < ActiveSupport::TestCase
    include InstanceAdministrationTestHelper
    self.use_transactional_tests = false

    setup do
      @administrator = users(:alice)
      @target = users(:bob)
      prepare_claimed_installation(administrator: @administrator)
      @target.update!(access_status: :active)
    end

    teardown do
      InstallationAuditEvent.delete_all
      Installation.delete_all
    end

    test "fails closed for unavailable, forbidden, and missing authority" do
      Installation.delete_all
      assert_equal :unavailable,
        RevokeCredentials.call(actor: @administrator, target: @target).status

      prepare_claimed_installation(administrator: @administrator)
      assert_equal :forbidden,
        RevokeCredentials.call(actor: @target, target: @target).status

      result = RevokeCredentials.call(actor: @administrator, target: nil)
      assert_equal :not_found, result.status
      event = InstallationAuditEvent.order(:id).last
      assert_equal "revoke_credentials", event.metadata.fetch("action")
      assert_equal "target_not_found", event.metadata.fetch("reason")
    end

    test "maps contention validation and database failures without leaking exceptions" do
      exhausted = DatabaseRetry::Exhausted.new(ActiveRecord::Deadlocked.new, attempts: 3)
      with_singleton_method_stub(DatabaseRetry, :call, ->(*) { raise exhausted }) do
        assert_equal :retryable_busy,
          RevokeCredentials.call(actor: @administrator, target: @target).status
      end

      invalid_user = User.new
      invalid_user.errors.add(:base, "cannot revoke")
      with_singleton_method_stub(
        DatabaseRetry,
        :call,
        ->(*) { raise ActiveRecord::RecordInvalid, invalid_user }
      ) do
        result = RevokeCredentials.call(actor: @administrator, target: @target)
        assert_equal :invalid, result.status
        assert_equal [ "cannot revoke" ], result.errors.fetch(:base)
      end

      with_singleton_method_stub(
        DatabaseRetry,
        :call,
        ->(*) { raise ActiveRecord::StatementInvalid, "database unavailable" }
      ) do
        assert_equal :unavailable,
          RevokeCredentials.call(actor: @administrator, target: @target).status
      end
    end
  end
end
