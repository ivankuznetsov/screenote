# frozen_string_literal: true

require "test_helper"
require_relative "../../support/instance_administration_test_helper"

module InstanceAccounts
  class CredentialRevokerTest < ActiveSupport::TestCase
    include InstanceAdministrationTestHelper
    self.use_transactional_tests = false

    setup do
      @administrator = users(:alice)
      @target = User.create!(email: "credential-revoker@example.test", password: "password123")
    end

    teardown do
      AuthenticationToken.delete_all
      User.where(email: "credential-revoker@example.test").delete_all
    end

    test "requires callers to hold an outer transaction" do
      error = assert_raises(RuntimeError) { CredentialRevoker.lock!(target: @target) }
      assert_equal "credential revocation requires an open outer transaction", error.message

      error = assert_raises(RuntimeError) { CredentialRevoker.revoke!(nil) }
      assert_equal "credential revocation requires an open outer transaction", error.message
    end

    test "skips terminal and explicitly preserved authentication credentials" do
      cancelled = create_recovery_token(subject: @target, issuer: @administrator)
      cancelled.token.transition_to!(:cancelled, at: Time.current)
      preserved = create_recovery_token(subject: @target, issuer: @administrator)
      result = nil

      ApplicationRecord.transaction do
        lock_set = CredentialRevoker.lock!(target: @target)
        result = CredentialRevoker.revoke!(
          lock_set,
          at: Time.current,
          preserve_authentication_token_id: preserved.token.id
        )
      end

      assert_equal 0, result.authentication_tokens
      assert cancelled.token.reload.cancelled?
      assert preserved.token.reload.outstanding?
    end
  end
end
