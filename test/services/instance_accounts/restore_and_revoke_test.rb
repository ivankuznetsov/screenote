# frozen_string_literal: true

require "test_helper"
require_relative "../../support/instance_administration_test_helper"

module InstanceAccounts
  class RestoreAndRevokeTest < ActiveSupport::TestCase
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

    test "restoration permits new credentials without resurrecting revoked ones" do
      old_session_id = @target.sessions.first!.id
      assert_equal :suspended, Suspend.call(actor: @administrator, target: @target).status

      result = Restore.call(actor: @administrator, target: @target)

      assert_equal :restored, result.status
      assert @target.reload.active?
      assert_not Session.exists?(old_session_id)
      assert api_keys(:bob_key).reload.revoked?
      assert AuthenticatedPrincipal.for_user(@target)
      assert_equal "account_restored", InstallationAuditEvent.order(:id).last.event_type
    end

    test "credential revocation leaves account active" do
      session_id = @target.sessions.first!.id

      result = RevokeCredentials.call(actor: @administrator, target: @target)

      assert_equal :revoked, result.status
      assert @target.reload.active?
      assert_not Session.exists?(session_id)
      assert api_keys(:bob_key).reload.revoked?
      assert_equal "credentials_revoked", InstallationAuditEvent.order(:id).last.event_type
    end

    test "a non administrator is denied and the attempt is audited" do
      result = Restore.call(actor: @target, target: @target)

      assert_equal :forbidden, result.status
      event = InstallationAuditEvent.order(:id).last
      assert_equal "instance_action_denied", event.event_type
      assert_equal @target, event.actor_user
      assert_equal "restore", event.metadata.fetch("action")
    end
  end
end
