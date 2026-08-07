# frozen_string_literal: true

require "test_helper"

class InstallationAuditEventTest < ActiveSupport::TestCase
  setup do
    InstallationAuditEvent.delete_all
    Installation.delete_all
    @installation = Installation.create!(
      singleton_key: Installation::SINGLETON_KEY,
      deployment_mode: "saas",
      state: "saas",
      storage_service: "rabata",
      storage_namespace_fingerprint: "a" * 64
    )
  end

  test "records a normalized append-only claim event" do
    event = @installation.audit_events.create!(
      actor_user: users(:alice),
      target_user: users(:alice),
      event_type: " Installation_Claimed ",
      metadata: {}
    )

    assert_equal "installation_claimed", event.event_type
    assert_equal({}, event.metadata)
    assert event.reload.readonly?
    assert_raises(ActiveRecord::ReadOnlyRecord) { event.update!(event_type: "changed") }
    assert_raises(ActiveRecord::ReadOnlyRecord) { event.destroy! }
  end

  test "requires structured metadata and a machine-readable event type" do
    event = @installation.audit_events.build(event_type: "not valid!", metadata: "detail")

    assert_not event.valid?
    assert event.errors[:event_type].any?
    assert event.errors[:metadata].any?
  end
end
