# frozen_string_literal: true

require "test_helper"

class SubscriptionTest < ActiveSupport::TestCase
  test "free plan limits" do
    sub = subscriptions(:bob_free)
    assert sub.free?
    assert_equal Subscription::FREE_PROJECT_LIMIT, sub.project_limit
    assert_equal Subscription::FREE_MEMBER_LIMIT, sub.member_limit
  end

  test "pro plan has unlimited limits" do
    sub = subscriptions(:alice_pro)
    assert sub.pro?
    assert_equal Float::INFINITY, sub.project_limit
    assert_equal Float::INFINITY, sub.member_limit
  end

  test "active_pro? returns true for active pro subscription" do
    sub = subscriptions(:alice_pro)
    assert sub.active_pro?
  end

  test "active_pro? returns false for free plan" do
    sub = subscriptions(:bob_free)
    assert_not sub.active_pro?
  end

  test "can_create_project? with free plan and no projects" do
    sub = subscriptions(:bob_free)
    assert sub.can_create_project?(0)
  end

  test "can_create_project? with free plan at limit" do
    sub = subscriptions(:bob_free)
    assert_not sub.can_create_project?(1)
  end

  test "can_create_project? with pro plan" do
    sub = subscriptions(:alice_pro)
    assert sub.can_create_project?(100)
  end

  test "can_invite_member? with free plan and no members" do
    sub = subscriptions(:bob_free)
    assert sub.can_invite_member?(0)
  end

  test "can_invite_member? with free plan at limit" do
    sub = subscriptions(:bob_free)
    assert_not sub.can_invite_member?(1)
  end

  test "can_invite_member? with pro plan" do
    sub = subscriptions(:alice_pro)
    assert sub.can_invite_member?(100)
  end

  test "validates stripe_customer_id uniqueness" do
    existing = subscriptions(:alice_pro)
    dup = Subscription.new(user: users(:unconfirmed), stripe_customer_id: existing.stripe_customer_id)
    assert_not dup.valid?
    assert_includes dup.errors[:stripe_customer_id], "has already been taken"
  end

  test "validates user_id uniqueness" do
    existing = subscriptions(:alice_pro)
    dup = Subscription.new(user: existing.user, stripe_customer_id: "cus_unique_test")
    assert_not dup.valid?
    assert_includes dup.errors[:user_id], "has already been taken"
  end
end
