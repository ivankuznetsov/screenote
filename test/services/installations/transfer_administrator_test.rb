# frozen_string_literal: true

require "test_helper"
require_relative "../../support/instance_administration_test_helper"

module Installations
  class TransferAdministratorTest < ActiveSupport::TestCase
    include InstanceAdministrationTestHelper
    self.use_transactional_tests = false

    setup do
      @administrator = users(:alice)
      @target = users(:bob)
      @installation = prepare_claimed_installation(administrator: @administrator)
      @target.update!(access_status: :active)
    end

    teardown do
      AuthenticationToken.delete_all
      InstallationAuditEvent.delete_all
      Installation.delete_all
    end

    test "atomically transfers authority and cancels predecessor issued recovery" do
      recovery = create_recovery_token(subject: @target, issuer: @administrator)

      result = TransferAdministrator.call(actor: @administrator, target: @target)

      assert_equal :transferred, result.status
      assert_equal @target, @installation.reload.administrator
      assert recovery.token.reload.cancelled?
      event = InstallationAuditEvent.order(:id).last
      assert_equal "administrator_transferred", event.event_type
      assert_equal @administrator, event.actor_user
      assert_equal @target, event.target_user
      assert_equal @administrator.id, event.metadata.fetch("previous_administrator_id")
      assert_equal 1, event.metadata.fetch("cancelled_recovery_tokens")

      stale = TransferAdministrator.call(actor: @administrator, target: users(:admin))
      assert_equal :stale_administrator, stale.status
    end

    test "rejects a suspended target without changing the administrator" do
      @target.update!(access_status: :suspended)

      result = TransferAdministrator.call(actor: @administrator, target: @target)

      assert_equal :target_inactive, result.status
      assert_equal @administrator, @installation.reload.administrator
    end

    test "operator channel can transfer only to an existing active account" do
      result = TransferAdministrator.call(
        actor: nil,
        target: @target,
        operator: true,
        channel: "local_operator"
      )

      assert_equal :transferred, result.status
      event = InstallationAuditEvent.order(:id).last
      assert_nil event.actor_user
      assert_equal "local_operator", event.metadata.fetch("channel")
    end

    test "missing installation and current target fail without mutation" do
      Installation.delete_all
      result = TransferAdministrator.call(actor: @administrator, target: @target)
      assert_equal :unavailable, result.status

      @installation = prepare_claimed_installation(administrator: @administrator)
      result = TransferAdministrator.call(actor: @administrator, target: @administrator)
      assert_equal :already_administrator, result.status
      assert_equal @administrator, result.user
      assert_equal @administrator, @installation.reload.administrator
      assert_equal 0, InstallationAuditEvent.count
    end

    test "missing target is denied and audited without changing authority" do
      result = TransferAdministrator.call(actor: @administrator, target: nil)

      assert_equal :not_found, result.status
      assert_equal @administrator, @installation.reload.administrator
      event = InstallationAuditEvent.find_by!(event_type: "instance_action_denied")
      assert_equal "target_not_found", event.metadata.fetch("reason")
      assert_nil event.target_user
    end

    test "missing actor is forbidden without changing authority or writing an audit event" do
      assert_no_difference "InstallationAuditEvent.count" do
        result = TransferAdministrator.call(actor: nil, target: @target)

        assert_equal :forbidden, result.status
        assert_nil result.user
      end

      assert_equal @administrator, @installation.reload.administrator
    end

    test "inactive stale administrator is forbidden after a transfer" do
      assert_equal :transferred,
        TransferAdministrator.call(actor: @administrator, target: @target).status
      @administrator.update!(access_status: :suspended)

      result = TransferAdministrator.call(actor: @administrator, target: users(:admin))

      assert_equal :forbidden, result.status
      assert_equal @target, @installation.reload.administrator
      event = InstallationAuditEvent.order(:id).last
      assert_equal "instance_action_denied", event.event_type
      assert_equal "forbidden", event.metadata.fetch("reason")
    end

    test "database retry exhaustion returns retryable busy" do
      exhausted = DatabaseRetry::Exhausted.new(StandardError.new("busy"), attempts: 3)

      with_singleton_method_stub(DatabaseRetry, :call, ->(**, &) { raise exhausted }) do
        result = TransferAdministrator.call(actor: @administrator, target: @target)

        assert_equal :retryable_busy, result.status
        assert_nil result.user
      end

      assert_equal @administrator, @installation.reload.administrator
    end

    test "audit validation failure rolls back transfer and returns field errors" do
      invalid_event = InstallationAuditEvent.new
      invalid_event.errors.add(:metadata, "must be recorded")

      with_singleton_method_stub(
        InstanceAdministration::Audit,
        :write!,
        ->(**) { raise ActiveRecord::RecordInvalid.new(invalid_event) }
      ) do
        result = TransferAdministrator.call(actor: @administrator, target: @target)

        assert_equal :invalid, result.status
        assert_equal [ "must be recorded" ], result.errors.fetch(:metadata)
      end

      assert_equal @administrator, @installation.reload.administrator
    end

    test "generic database failure is unavailable without changing authority" do
      with_singleton_method_stub(
        InstanceAdministration::Authority,
        :lock,
        ->(**) { raise ActiveRecord::StatementInvalid, "database unavailable" }
      ) do
        result = TransferAdministrator.call(actor: @administrator, target: @target)

        assert_equal :unavailable, result.status
        assert_nil result.user
      end

      assert_equal @administrator, @installation.reload.administrator
    end

    test "operation serialization reports identifiers without implicit target lookup" do
      operation = TransferAdministrator.new(actor: @administrator, target: @target)
      anonymous = TransferAdministrator.new(actor: nil, target: nil, operator: true)

      assert_match(/actor_id=#{@administrator.id}/, operation.inspect)
      assert_match(/target_id=#{@target.id}/, operation.to_s)
      assert_equal @administrator.id, operation.as_json.fetch("actor_id")
      assert_equal @target.id, operation.as_json.fetch("target_id")
      assert_match(/actor_id=nil target_id=nil/, anonymous.inspect)
      assert_nil anonymous.as_json.fetch("actor_id")
      assert_nil anonymous.as_json.fetch("target_id")
    end
  end
end
