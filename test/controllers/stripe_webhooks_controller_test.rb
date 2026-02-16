# frozen_string_literal: true

require "test_helper"
require "ostruct"

class StripeWebhooksControllerTest < ActionDispatch::IntegrationTest
  WEBHOOK_SECRET = "whsec_test_secret"

  setup do
    ENV["STRIPE_WEBHOOK_SECRET"] = WEBHOOK_SECRET
    @subscription = subscriptions(:bob_free)
  end

  teardown do
    ENV.delete("STRIPE_WEBHOOK_SECRET")
  end

  test "rejects invalid signature" do
    post stripe_webhooks_path,
      params: "{}",
      headers: { "HTTP_STRIPE_SIGNATURE" => "invalid", "CONTENT_TYPE" => "application/json" }
    assert_response :bad_request
  end

  test "returns ok for unhandled event types" do
    post_webhook(build_event("invoice.payment_succeeded", {}))
    assert_response :ok
  end

  test "checkout.session.completed upgrades subscription to pro" do
    event = build_event("checkout.session.completed", {
      customer: @subscription.stripe_customer_id,
      subscription: "sub_new_test_123"
    })

    stripe_sub_mock = OpenStruct.new(
      id: "sub_new_test_123",
      status: "active",
      current_period_end: 30.days.from_now.to_i
    )
    original_method = Stripe::Subscription.method(:retrieve)
    Stripe::Subscription.define_singleton_method(:retrieve) { |_id| stripe_sub_mock }
    post_webhook(event)
  ensure
    Stripe::Subscription.define_singleton_method(:retrieve, original_method)

    assert_response :ok
    @subscription.reload
    assert @subscription.pro?, "Subscription should be upgraded to pro"
    assert @subscription.status_active?, "Subscription status should be active"
    assert_equal "sub_new_test_123", @subscription.stripe_subscription_id
    assert_not_nil @subscription.current_period_end, "current_period_end should be set"
  end

  test "checkout.session.completed with missing subscription record returns ok and notifies" do
    event = build_event("checkout.session.completed", {
      customer: "cus_nonexistent",
      subscription: "sub_orphan"
    })

    post_webhook(event)
    assert_response :ok
  end

  test "checkout.session.completed with nil session.subscription skips retrieval" do
    event = build_event("checkout.session.completed", {
      customer: @subscription.stripe_customer_id,
      subscription: nil
    })

    post_webhook(event)
    assert_response :ok
    @subscription.reload
    assert @subscription.free?, "Subscription should remain free when session.subscription is nil"
  end

  test "customer.subscription.updated sets active status" do
    upgrade_bob_to_pro!

    event = build_event("customer.subscription.updated", {
      customer: @subscription.stripe_customer_id,
      status: "active",
      current_period_end: 60.days.from_now.to_i
    })

    post_webhook(event)
    assert_response :ok
    @subscription.reload
    assert @subscription.status_active?, "Status should be active"
  end

  test "customer.subscription.updated sets past_due status" do
    upgrade_bob_to_pro!

    event = build_event("customer.subscription.updated", {
      customer: @subscription.stripe_customer_id,
      status: "past_due",
      current_period_end: 30.days.from_now.to_i
    })

    post_webhook(event)
    assert_response :ok
    @subscription.reload
    assert @subscription.status_past_due?, "Status should be past_due"
  end

  test "customer.subscription.updated maps canceled status" do
    upgrade_bob_to_pro!

    event = build_event("customer.subscription.updated", {
      customer: @subscription.stripe_customer_id,
      status: "canceled",
      current_period_end: 30.days.from_now.to_i
    })

    post_webhook(event)
    assert_response :ok
    @subscription.reload
    assert @subscription.status_canceled?, "Status should be canceled"
  end

  test "customer.subscription.updated maps unpaid to canceled" do
    upgrade_bob_to_pro!

    event = build_event("customer.subscription.updated", {
      customer: @subscription.stripe_customer_id,
      status: "unpaid",
      current_period_end: 30.days.from_now.to_i
    })

    post_webhook(event)
    assert_response :ok
    @subscription.reload
    assert @subscription.status_canceled?, "Unpaid status should map to canceled"
  end

  test "customer.subscription.updated maps unknown status to incomplete" do
    upgrade_bob_to_pro!

    event = build_event("customer.subscription.updated", {
      customer: @subscription.stripe_customer_id,
      status: "trialing",
      current_period_end: 30.days.from_now.to_i
    })

    post_webhook(event)
    assert_response :ok
    @subscription.reload
    assert @subscription.status_incomplete?, "Unknown status should map to incomplete"
  end

  test "customer.subscription.deleted resets to free plan" do
    upgrade_bob_to_pro!

    event = build_event("customer.subscription.deleted", {
      customer: @subscription.stripe_customer_id
    })

    post_webhook(event)
    assert_response :ok
    @subscription.reload
    assert @subscription.free?, "Plan should be reset to free"
    assert @subscription.status_canceled?, "Status should be canceled"
    assert_nil @subscription.stripe_subscription_id, "stripe_subscription_id should be cleared"
  end

  private

  def upgrade_bob_to_pro!
    @subscription.update_columns(
      plan: :pro,
      status: :active,
      stripe_subscription_id: "sub_bob_test",
      current_period_end: 30.days.from_now
    )
  end

  def build_event(type, data)
    {
      id: "evt_test_#{SecureRandom.hex(8)}",
      object: "event",
      type: type,
      data: { object: data }
    }
  end

  def post_webhook(event_data)
    payload = event_data.to_json
    timestamp = Time.now.to_i
    signature = compute_signature(timestamp, payload)
    sig_header = "t=#{timestamp},v1=#{signature}"

    post stripe_webhooks_path,
      params: payload,
      headers: {
        "HTTP_STRIPE_SIGNATURE" => sig_header,
        "CONTENT_TYPE" => "application/json"
      }
  end

  def compute_signature(timestamp, payload)
    signed_payload = "#{timestamp}.#{payload}"
    OpenSSL::HMAC.hexdigest("SHA256", WEBHOOK_SECRET, signed_payload)
  end
end
