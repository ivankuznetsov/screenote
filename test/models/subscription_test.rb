# frozen_string_literal: true

require "test_helper"

class SubscriptionTest < ActiveSupport::TestCase
  test "free plan constants" do
    assert_equal 1, Subscription::FREE_PROJECT_LIMIT
    assert_equal 1, Subscription::FREE_MEMBER_LIMIT
    assert_equal 1000, Subscription::PRO_PRICE_CENTS
  end

  test "active_pro? returns true for active pro subscription" do
    sub = subscriptions(:alice_pro)
    assert sub.active_pro?, "Active pro subscription should be active_pro?"
  end

  test "active_pro? returns false for free plan" do
    sub = subscriptions(:bob_free)
    assert_not sub.active_pro?, "Free subscription should not be active_pro?"
  end

  test "active_pro? returns false for pro plan with past_due status" do
    sub = subscriptions(:alice_pro)
    sub.status_past_due!
    assert_not sub.active_pro?, "Pro subscription with past_due status should not be active_pro?"
  end

  test "active_pro? returns false for pro plan with canceled status" do
    sub = subscriptions(:alice_pro)
    sub.update_columns(status: :canceled, stripe_subscription_id: nil) # bypass validations for test
    assert_not sub.active_pro?, "Pro subscription with canceled status should not be active_pro?"
  end

  test "validates stripe_customer_id presence" do
    sub = Subscription.new(user: users(:unconfirmed), stripe_customer_id: nil)
    assert_not sub.valid?, "Subscription should be invalid without stripe_customer_id"
    assert_includes sub.errors[:stripe_customer_id], "can't be blank"
  end

  test "validates stripe_customer_id uniqueness" do
    existing = subscriptions(:alice_pro)
    dup = Subscription.new(user: users(:unconfirmed), stripe_customer_id: existing.stripe_customer_id)
    assert_not dup.valid?, "Subscription should be invalid with duplicate stripe_customer_id"
    assert_includes dup.errors[:stripe_customer_id], "has already been taken"
  end

  test "validates user_id uniqueness" do
    existing = subscriptions(:alice_pro)
    dup = Subscription.new(user: existing.user, stripe_customer_id: "cus_unique_test")
    assert_not dup.valid?, "Subscription should be invalid with duplicate user_id"
    assert_includes dup.errors[:user_id], "has already been taken"
  end

  test "validates stripe_subscription_id required for active pro" do
    sub = Subscription.new(
      user: users(:unconfirmed),
      stripe_customer_id: "cus_test_validation",
      plan: :pro,
      status: :active,
      stripe_subscription_id: nil,
      current_period_end: 30.days.from_now
    )
    assert_not sub.valid?, "Active pro subscription should require stripe_subscription_id"
    assert_includes sub.errors[:stripe_subscription_id], "can't be blank"
  end

  test "validates current_period_end required for active pro" do
    sub = Subscription.new(
      user: users(:unconfirmed),
      stripe_customer_id: "cus_test_validation",
      plan: :pro,
      status: :active,
      stripe_subscription_id: "sub_test_123",
      current_period_end: nil
    )
    assert_not sub.valid?, "Active pro subscription should require current_period_end"
    assert_includes sub.errors[:current_period_end], "can't be blank"
  end

  test "free plan does not require stripe_subscription_id" do
    sub = Subscription.new(
      user: users(:unconfirmed),
      stripe_customer_id: "cus_test_free",
      plan: :free,
      status: :incomplete,
      stripe_subscription_id: nil,
      current_period_end: nil
    )
    assert sub.valid?, "Free plan should not require stripe_subscription_id: #{sub.errors.full_messages}"
  end
end
