# frozen_string_literal: true

require "test_helper"
require_relative "../../support/instance_administration_test_helper"

module InstanceAdministration
  class AuditTest < ActiveSupport::TestCase
    include InstanceAdministrationTestHelper

    setup do
      @administrator = users(:alice)
      @target = users(:bob)
      @installation = prepare_claimed_installation(administrator: @administrator)
    end

    test "writes bounded metadata and normalizes an untrusted channel" do
      long_key = "key" * 30
      long_value = "value" * 40

      event = Audit.write!(
        installation: @installation,
        actor: @administrator,
        target: @target,
        event_type: "administrator_transferred",
        channel: " WEB/../../private ",
        metadata: {
          long_key => long_value,
          "count" => 2,
          "allowed" => true,
          "missing" => nil
        }
      )

      assert_equal "unknown", event.metadata.fetch("channel")
      assert_equal long_value.first(128), event.metadata.fetch(long_key.first(64))
      assert_equal 2, event.metadata.fetch("count")
      assert_equal true, event.metadata.fetch("allowed")
      assert_nil event.metadata.fetch("missing")
    end

    test "writes a denial only for a durable actor" do
      assert_no_difference("InstallationAuditEvent.count") do
        assert_nil Audit.denied!(
          installation: @installation,
          actor: nil,
          target: @target,
          action: :transfer_administrator,
          reason: :forbidden
        )
      end

      event = nil
      assert_difference("InstallationAuditEvent.count", 1) do
        event = Audit.denied!(
          installation: @installation,
          actor: @administrator,
          target: @target,
          action: :transfer_administrator,
          reason: :forbidden,
          channel: "local_operator"
        )
      end

      assert_equal "instance_action_denied", event.event_type
      assert_equal "transfer_administrator", event.metadata.fetch("action")
      assert_equal "forbidden", event.metadata.fetch("reason")
      assert_equal "local_operator", event.metadata.fetch("channel")
    end
  end
end
