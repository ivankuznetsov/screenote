# frozen_string_literal: true

require "test_helper"

class StripeWebhookEventTest < ActiveSupport::TestCase
  test "stripe_event_id is required" do
    event = StripeWebhookEvent.new(stripe_event_id: nil)
    assert_not event.valid?
    assert_includes event.errors[:stripe_event_id], "can't be blank"
  end

  test "stripe_event_id is unique" do
    StripeWebhookEvent.create!(stripe_event_id: "evt_test_123")
    duplicate = StripeWebhookEvent.new(stripe_event_id: "evt_test_123")
    assert_not duplicate.valid?
    assert_includes duplicate.errors[:stripe_event_id], "has already been taken"
  end

  test "unique index enforces uniqueness at database level" do
    StripeWebhookEvent.create!(stripe_event_id: "evt_test_456")
    assert_raises(ActiveRecord::RecordNotUnique) do
      StripeWebhookEvent.new(stripe_event_id: "evt_test_456").save(validate: false)
    end
  end
end
