# frozen_string_literal: true

require "test_helper"

class StripeWebhooksControllerTest < ActionDispatch::IntegrationTest
  WEBHOOK_SECRET = "whsec_test_secret"

  setup do
    ENV["STRIPE_WEBHOOK_SECRET"] = WEBHOOK_SECRET
    @subscription = subscriptions(:bob_free)
    @stripe_retrieve_stub = Stripe::Subscription.method(:retrieve)
    Stripe::Subscription.singleton_class.define_method(:retrieve) do |id|
      Stripe::Subscription.construct_from(
        id: id,
        customer: "cus_stub",
        status: "active",
        items: { object: "list", data: [ { current_period_end: 30.days.from_now.to_i } ] }
      )
    end
  end

  teardown do
    ENV.delete("STRIPE_WEBHOOK_SECRET")
    Stripe::Subscription.singleton_class.define_method(:retrieve, @stripe_retrieve_stub) if @stripe_retrieve_stub
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

  test "returns not found when the billing capability is unavailable" do
    deployment = Struct.new(:billing?).new(false)

    with_singleton_method(Screenote::Deployment, :current, -> { deployment }) do
      post stripe_webhooks_path,
        params: "{}",
        headers: { "HTTP_STRIPE_SIGNATURE" => "valid", "CONTENT_TYPE" => "application/json" }
    end

    assert_response :not_found
  end

  test "permanent validation failures are acknowledged with redacted event context" do
    record = Subscription.new
    record.errors.add(:base, "invalid")
    error = ActiveRecord::RecordInvalid.new(record)
    notifications = []

    with_singleton_method(Stripe::Webhook, :construct_event, ->(*) { raise error }) do
      with_singleton_method(Screenote::Monitoring, :notify, ->(raised, context:) { notifications << [ raised, context ] }) do
        post stripe_webhooks_path,
          params: "{}",
          headers: { "HTTP_STRIPE_SIGNATURE" => "valid", "CONTENT_TYPE" => "application/json" }
      end
    end

    assert_response :ok
    assert_equal error, notifications.dig(0, 0)
    assert_nil notifications.dig(0, 1, :event_type)
    assert_nil notifications.dig(0, 1, :event_id)
  end

  test "validation failures after parsing include the event identity" do
    event = build_subscription_updated_event(status: "active", current_period_end: 60.days.from_now.to_i)
    record = Subscription.new
    record.errors.add(:base, "invalid")
    error = ActiveRecord::RecordInvalid.new(record)
    notifications = []
    failing_lock = ->(*, **) { raise error }

    subscription = @subscription
    with_singleton_method(Subscription, :find_by, ->(*, **) { subscription }) do
      with_singleton_method(@subscription, :with_lock, failing_lock) do
        with_singleton_method(Screenote::Monitoring, :notify, ->(raised, context:) { notifications << [ raised, context ] }) do
          post_webhook(event)
        end
      end
    end

    assert_response :ok
    assert_equal event[:type], notifications.dig(0, 1, :event_type)
    assert_equal event[:id], notifications.dig(0, 1, :event_id)
  end

  test "Stripe transport failures return retryable errors with or without a parsed event" do
    notifications = []
    connection_error = Stripe::APIConnectionError.new("unavailable")
    with_singleton_method(Screenote::Monitoring, :notify, ->(raised, context:) { notifications << [ raised, context ] }) do
      with_singleton_method(Stripe::Webhook, :construct_event, ->(*) { raise connection_error }) do
        post stripe_webhooks_path,
          params: "{}",
          headers: { "HTTP_STRIPE_SIGNATURE" => "valid", "CONTENT_TYPE" => "application/json" }
      end
      assert_response :internal_server_error
      assert_nil notifications.last.dig(1, :event_id)

      event = build_event("checkout.session.completed", {
        customer: @subscription.stripe_customer_id,
        subscription: "sub-unavailable"
      })
      with_singleton_method(Stripe::Subscription, :retrieve, ->(*) { raise connection_error }) { post_webhook(event) }
      assert_response :internal_server_error
      assert_equal event[:id], notifications.last.dig(1, :event_id)
    end
  end

  test "mail failure after activation is monitored without failing the webhook" do
    @subscription.update_columns(
      plan: :pro,
      status: :incomplete,
      stripe_subscription_id: "sub_bob_test",
      current_period_end: 30.days.from_now
    )
    event = build_subscription_updated_event(status: "active", current_period_end: 60.days.from_now.to_i)
    error = StandardError.new("mailer unavailable")
    delivery = Object.new
    delivery.define_singleton_method(:deliver_later) { raise error }
    notifications = []

    with_singleton_method(AdminMailer, :new_pro_subscriber, ->(*) { delivery }) do
      with_singleton_method(Screenote::Monitoring, :notify, ->(raised, context:) { notifications << [ raised, context ] }) do
        post_webhook(event)
      end
    end

    assert_response :ok
    assert_equal error, notifications.dig(0, 0)
    assert_equal @subscription.user_id, notifications.dig(0, 1, :user_id)
  end

  test "idempotency: replayed event with same id is short-circuited and does not re-trigger mail" do
    @subscription.update_columns(
      plan: :pro,
      status: :incomplete,
      stripe_subscription_id: "sub_bob_test",
      current_period_end: 30.days.from_now
    )
    event = build_subscription_updated_event(status: "active", current_period_end: 60.days.from_now.to_i)

    assert_enqueued_emails 1 do
      post_webhook(event)
    end
    assert_response :ok
    assert_equal 1, StripeWebhookEvent.where(stripe_event_id: event[:id]).count

    assert_no_enqueued_emails do
      post_webhook(event)
    end
    assert_response :ok
    assert_equal 1, StripeWebhookEvent.where(stripe_event_id: event[:id]).count,
      "Replayed event should not create a duplicate StripeWebhookEvent row"
  end

  test "checkout.session.completed upgrades subscription to pro" do
    event = build_event("checkout.session.completed", {
      customer: @subscription.stripe_customer_id,
      subscription: "sub_new_test_123"
    })

    post_webhook(event)

    assert_response :ok
    @subscription.reload
    assert @subscription.pro?, "Subscription should be upgraded to pro"
    assert @subscription.active?, "Subscription should be active after successful checkout"
    assert_equal "sub_new_test_123", @subscription.stripe_subscription_id
    assert_not_nil @subscription.current_period_end, "current_period_end should be set"
  end

  test "checkout.session.completed with missing subscription record returns service_unavailable" do
    event = build_event("checkout.session.completed", {
      customer: "cus_nonexistent",
      subscription: "sub_orphan"
    })

    post_webhook(event)
    assert_response :service_unavailable
  end

  test "customer.subscription.updated with missing subscription record returns service_unavailable" do
    event = build_event("customer.subscription.updated", {
      id: "sub_orphan",
      customer: "cus_nonexistent",
      status: "active",
      items: { object: "list", data: [] }
    })

    post_webhook(event)

    assert_response :service_unavailable
  end

  test "customer.subscription.deleted with missing subscription record returns service_unavailable" do
    event = build_event("customer.subscription.deleted", {
      id: "sub_orphan",
      customer: "cus_nonexistent"
    })

    post_webhook(event)

    assert_response :service_unavailable
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

  test "customer.subscription.updated sets active status and plan pro" do
    upgrade_bob_to_pro!
    period_end = 60.days.from_now.to_i

    event = build_subscription_updated_event(status: "active", current_period_end: period_end)

    post_webhook(event)
    assert_response :ok
    @subscription.reload
    assert @subscription.active?, "Status should be active"
    assert @subscription.pro?, "Plan should remain pro when stripe_subscription_id is present"
    assert_equal Time.at(period_end).utc.to_i, @subscription.current_period_end.to_i,
      "current_period_end should be read from items.data[0]"
  end

  test "customer.subscription.updated sets past_due status" do
    upgrade_bob_to_pro!

    event = build_subscription_updated_event(status: "past_due", current_period_end: 30.days.from_now.to_i)

    post_webhook(event)
    assert_response :ok
    @subscription.reload
    assert @subscription.past_due?, "Status should be past_due"
  end

  test "customer.subscription.updated maps canceled status" do
    upgrade_bob_to_pro!

    event = build_subscription_updated_event(status: "canceled", current_period_end: 30.days.from_now.to_i)

    post_webhook(event)
    assert_response :ok
    @subscription.reload
    assert @subscription.canceled?, "Status should be canceled"
  end

  test "customer.subscription.updated maps unpaid to canceled" do
    upgrade_bob_to_pro!

    event = build_subscription_updated_event(status: "unpaid", current_period_end: 30.days.from_now.to_i)

    post_webhook(event)
    assert_response :ok
    @subscription.reload
    assert @subscription.canceled?, "Unpaid status should map to canceled"
  end

  test "customer.subscription.updated maps unknown status to incomplete" do
    upgrade_bob_to_pro!

    event = build_subscription_updated_event(status: "paused", current_period_end: 30.days.from_now.to_i)

    post_webhook(event)
    assert_response :ok
    @subscription.reload
    assert @subscription.incomplete?, "Unknown status should map to incomplete"
  end

  test "customer.subscription.updated maps trialing to active so trial users keep access" do
    upgrade_bob_to_pro!

    event = build_subscription_updated_event(status: "trialing", current_period_end: 14.days.from_now.to_i)

    post_webhook(event)
    assert_response :ok
    @subscription.reload
    assert @subscription.active?, "Trialing should map to active"
    assert @subscription.pro?, "Plan should remain pro during trial"
  end

  test "customer.subscription.updated succeeds when current_period_end is absent from subscription object (Stripe 2026-01 API)" do
    # Regression test for production NoMethodError: undefined method 'current_period_end'
    # for #<Stripe::Subscription>. In Stripe API version 2026-01-28 and later,
    # current_period_end was removed from the Subscription object and moved onto each item.
    upgrade_bob_to_pro!
    original_period_end = @subscription.current_period_end
    new_period_end = 60.days.from_now.to_i

    event = {
      id: "evt_test_#{SecureRandom.hex(8)}",
      object: "event",
      type: "customer.subscription.updated",
      data: {
        object: {
          id: "sub_bob_test",
          object: "subscription",
          customer: @subscription.stripe_customer_id,
          status: "active",
          items: {
            object: "list",
            data: [ {
              id: "si_test",
              object: "subscription_item",
              current_period_end: new_period_end,
              current_period_start: 30.days.ago.to_i
            } ]
          }
        }
      }
    }

    post_webhook(event)
    assert_response :ok
    @subscription.reload
    assert @subscription.active?, "Status should be active"
    assert @subscription.pro?, "Plan should remain pro"
    assert_not_equal original_period_end.to_i, @subscription.current_period_end.to_i,
      "current_period_end should be updated from items.data[0].current_period_end"
    assert_equal Time.at(new_period_end).utc.to_i, @subscription.current_period_end.to_i,
      "current_period_end should match items.data[0].current_period_end"
  end

  test "customer.subscription.updated tolerates empty items list" do
    upgrade_bob_to_pro!
    original_period_end = @subscription.current_period_end

    event = build_event("customer.subscription.updated", {
      customer: @subscription.stripe_customer_id,
      status: "active",
      items: { object: "list", data: [] }
    })

    post_webhook(event)
    assert_response :ok
    @subscription.reload
    assert @subscription.active?, "Status should still update"
    assert_equal original_period_end.to_i, @subscription.current_period_end.to_i,
      "current_period_end should be preserved when items.data is empty"
  end

  test "checkout.session.completed preserves active status when subscription.updated arrived first" do
    # Simulate subscription.updated arriving first and setting active status
    @subscription.update_columns(
      plan: :free,
      status: :active,
      stripe_subscription_id: nil,
      current_period_end: 60.days.from_now
    )

    event = build_event("checkout.session.completed", {
      customer: @subscription.stripe_customer_id,
      subscription: "sub_new_test_456"
    })

    post_webhook(event)
    assert_response :ok
    @subscription.reload
    assert @subscription.pro?, "Plan should be upgraded to pro"
    assert @subscription.active?, "Status should remain active, not be downgraded to incomplete"
    assert_equal "sub_new_test_456", @subscription.stripe_subscription_id
  end

  test "out-of-order webhooks: subscription.updated then checkout.session.completed does not strand user" do
    # Step 1: subscription.updated arrives first with active status
    # At this point, no stripe_subscription_id is set, so plan should NOT be set to pro
    sub_updated_event = build_subscription_updated_event(status: "active", current_period_end: 60.days.from_now.to_i)

    post_webhook(sub_updated_event)
    assert_response :ok
    @subscription.reload
    assert @subscription.active?, "Status should be active after subscription.updated"
    assert @subscription.free?, "Plan should remain free since stripe_subscription_id was not yet set"

    # Step 2: checkout.session.completed arrives second
    checkout_event = build_event("checkout.session.completed", {
      customer: @subscription.stripe_customer_id,
      subscription: "sub_out_of_order_123"
    })

    post_webhook(checkout_event)
    assert_response :ok
    @subscription.reload
    assert @subscription.pro?, "Plan should be pro after checkout"
    assert @subscription.active?, "Status should remain active, not be downgraded to incomplete"
    assert_equal "sub_out_of_order_123", @subscription.stripe_subscription_id
  end

  test "customer.subscription.updated sends email when transitioning to active pro" do
    # Simulate checkout completed first (sets plan to pro, status incomplete)
    @subscription.update_columns(
      plan: :pro,
      status: :incomplete,
      stripe_subscription_id: "sub_new_test",
      current_period_end: 30.days.from_now
    )

    event = build_subscription_updated_event(status: "active", current_period_end: 60.days.from_now.to_i)

    assert_enqueued_emails 1 do
      post_webhook(event)
    end
    assert_response :ok
  end

  test "customer.subscription.updated does not send email when already active pro" do
    upgrade_bob_to_pro!

    event = build_subscription_updated_event(status: "active", current_period_end: 60.days.from_now.to_i)

    assert_no_enqueued_emails do
      post_webhook(event)
    end
    assert_response :ok
  end

  test "customer.subscription.updated does not send email when status is not active" do
    @subscription.update_columns(
      plan: :pro,
      status: :incomplete,
      stripe_subscription_id: "sub_new_test",
      current_period_end: 30.days.from_now
    )

    event = build_subscription_updated_event(status: "past_due", current_period_end: 60.days.from_now.to_i)

    assert_no_enqueued_emails do
      post_webhook(event)
    end
    assert_response :ok
  end

  test "checkout.session.completed does not send email" do
    event = build_event("checkout.session.completed", {
      customer: @subscription.stripe_customer_id,
      subscription: "sub_no_email_test"
    })

    assert_no_enqueued_emails do
      post_webhook(event)
    end
    assert_response :ok
  end

  test "customer.subscription.deleted resets to free plan" do
    upgrade_bob_to_pro!

    event = build_event("customer.subscription.deleted", {
      id: @subscription.stripe_subscription_id,
      customer: @subscription.stripe_customer_id
    })

    post_webhook(event)
    assert_response :ok
    @subscription.reload
    assert @subscription.free?, "Plan should be reset to free"
    assert @subscription.canceled?, "Status should be canceled"
    assert_nil @subscription.stripe_subscription_id, "stripe_subscription_id should be cleared"
  end

  test "customer.subscription.deleted ignores events for a different subscription on the same customer" do
    # Guards against a Stripe customer having multiple subscriptions where the
    # tracked one is still active but a different one is being deleted.
    upgrade_bob_to_pro!

    event = build_event("customer.subscription.deleted", {
      id: "sub_some_other_subscription",
      customer: @subscription.stripe_customer_id
    })

    post_webhook(event)
    assert_response :ok
    @subscription.reload
    assert @subscription.pro?, "Plan should remain pro — the deleted sub is not ours"
    assert @subscription.active?, "Status should remain active"
    assert_equal "sub_bob_test", @subscription.stripe_subscription_id,
      "stripe_subscription_id should not be cleared when a different sub is deleted"
  end

  test "customer.subscription.updated ignores events for a different subscription on the same customer" do
    upgrade_bob_to_pro!
    original_period_end = @subscription.current_period_end

    event = build_event("customer.subscription.updated", {
      id: "sub_some_other_subscription",
      object: "subscription",
      customer: @subscription.stripe_customer_id,
      status: "canceled",
      items: {
        object: "list",
        data: [ { id: "si_other", object: "subscription_item", current_period_end: 1.day.from_now.to_i } ]
      }
    })

    post_webhook(event)
    assert_response :ok
    @subscription.reload
    assert @subscription.active?, "Status should remain active — the updated sub is not ours"
    assert @subscription.pro?, "Plan should remain pro"
    assert_equal original_period_end.to_i, @subscription.current_period_end.to_i,
      "current_period_end should not be overwritten by a different sub's event"
  end

  private

  def with_singleton_method(receiver, name, replacement)
    original = receiver.method(name)
    receiver.define_singleton_method(name, replacement)
    yield
  ensure
    receiver.define_singleton_method(name, original) if original
  end

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

  # Builds a customer.subscription.updated event matching the Stripe 2026-01-28 API shape,
  # where current_period_end lives on each subscription item, not on the subscription itself.
  def build_subscription_updated_event(status:, current_period_end:)
    build_event("customer.subscription.updated", {
      id: @subscription.stripe_subscription_id || "sub_bob_test",
      object: "subscription",
      customer: @subscription.stripe_customer_id,
      status: status,
      items: {
        object: "list",
        data: [ {
          id: "si_test",
          object: "subscription_item",
          current_period_end: current_period_end,
          current_period_start: 30.days.ago.to_i
        } ]
      }
    })
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
