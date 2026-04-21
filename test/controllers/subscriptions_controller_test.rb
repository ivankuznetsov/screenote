# frozen_string_literal: true

require "test_helper"
require "ostruct"

class SubscriptionsControllerTest < ActionDispatch::IntegrationTest
  test "requires authentication" do
    get subscription_path
    assert_redirected_to new_session_path
  end

  test "show renders billing page for free user" do
    sign_in(users(:bob))
    get subscription_path
    assert_response :success
    assert_select ".billing-plan__name", "Free"
    assert_select ".billing-plan__name", "Pro"
  end

  test "show displays upgrade button for free user" do
    sign_in(users(:bob))
    get subscription_path
    assert_response :success
    assert_select "button", "Upgrade to Pro"
  end

  test "show displays manage button for pro user" do
    sign_in(users(:alice))
    get subscription_path
    assert_response :success
    assert_select "button", "Manage subscription"
  end

  test "show displays current plan badge" do
    sign_in(users(:bob))
    get subscription_path
    assert_response :success
    assert_select ".billing-plan__badge", "Current"
  end

  test "show uses PRO_PRICE_CENTS constant for price display" do
    sign_in(users(:bob))
    get subscription_path
    assert_response :success
    assert_select ".billing-plan__amount", /\$#{Subscription::PRO_PRICE_CENTS / 100}/
  end

  test "show displays pending activation message when status=success but not yet pro" do
    sign_in(users(:bob))
    get subscription_path(status: "success")
    assert_response :success
    assert_select ".flash--notice", /being activated/
  end

  test "show displays welcome message when status=success and already pro" do
    sign_in(users(:alice))
    get subscription_path(status: "success")
    assert_response :success
    assert_select ".flash--notice", /Welcome to Pro/
  end

  test "show displays canceled message" do
    sign_in(users(:bob))
    get subscription_path(status: "canceled")
    assert_response :success
    assert_select ".flash--alert", /canceled/
  end

  # -- checkout action --

  test "checkout redirects pro users back with notice" do
    sign_in(users(:alice))
    post checkout_subscription_path
    assert_redirected_to subscription_path
    assert_equal "You're already on the Pro plan.", flash[:notice]
  end

  test "checkout redirects users with a tracked stripe_subscription_id to the portal (past_due loophole)" do
    # Regression: prior to this guard, a user whose subscription went past_due
    # (status != active, so pro? returned false) could create a second Stripe
    # sub by clicking Upgrade again — leading to double billing.
    sign_in(users(:bob))
    users(:bob).subscription.update!(
      plan: :pro,
      status: :past_due,
      stripe_customer_id: "cus_past_due",
      stripe_subscription_id: "sub_past_due_bob",
      current_period_end: 1.day.ago
    )

    post checkout_subscription_path
    assert_redirected_to subscription_path
    assert_match(/billing portal/, flash[:alert])
  end

  test "checkout for free user creates Stripe session and redirects" do
    sign_in(users(:bob))

    original_create = Stripe::Checkout::Session.method(:create)
    Stripe::Checkout::Session.define_singleton_method(:create) do |**_args|
      OpenStruct.new(url: "https://checkout.stripe.com/test")
    end

    begin
      ENV["STRIPE_PRO_PRICE_ID"] = "price_test_123"
      post checkout_subscription_path
      assert_redirected_to "https://checkout.stripe.com/test"
    ensure
      ENV.delete("STRIPE_PRO_PRICE_ID")
      Stripe::Checkout::Session.define_singleton_method(:create, original_create)
    end
  end

  test "checkout when Stripe raises error shows friendly alert" do
    sign_in(users(:bob))

    original_create = Stripe::Checkout::Session.method(:create)
    Stripe::Checkout::Session.define_singleton_method(:create) do |**_args|
      raise Stripe::StripeError.new("test")
    end

    begin
      ENV["STRIPE_PRO_PRICE_ID"] = "price_test_123"
      post checkout_subscription_path
      assert_redirected_to subscription_path
      assert_match(/payment provider/, flash[:alert])
    ensure
      ENV.delete("STRIPE_PRO_PRICE_ID")
      Stripe::Checkout::Session.define_singleton_method(:create, original_create)
    end
  end

  # -- portal action --

  test "portal with no subscription shows alert" do
    user = User.create!(email: "nosub@example.com", password: "password123", confirmed_at: Time.current)
    sign_in(user)
    post portal_subscription_path
    assert_redirected_to subscription_path
    assert_equal "No billing account found.", flash[:alert]
  end

  test "portal with subscription redirects to Stripe portal" do
    sign_in(users(:alice))

    original_create = Stripe::BillingPortal::Session.method(:create)
    Stripe::BillingPortal::Session.define_singleton_method(:create) do |**_args|
      OpenStruct.new(url: "https://billing.stripe.com/test")
    end

    begin
      post portal_subscription_path
      assert_redirected_to "https://billing.stripe.com/test"
    ensure
      Stripe::BillingPortal::Session.define_singleton_method(:create, original_create)
    end
  end
end
