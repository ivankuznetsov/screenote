# frozen_string_literal: true

class SubscriptionsController < ApplicationController
  def show
    @subscription = Current.user.subscription
  end

  def checkout
    subscription = find_or_create_subscription

    checkout_session = Stripe::Checkout::Session.create(
      customer: subscription.stripe_customer_id,
      mode: "subscription",
      line_items: [ { price: ENV.fetch("STRIPE_PRO_PRICE_ID"), quantity: 1 } ],
      success_url: subscription_url(status: "success"),
      cancel_url: subscription_url(status: "canceled")
    )

    redirect_to checkout_session.url, allow_other_host: true
  end

  def portal
    subscription = Current.user.subscription
    unless subscription
      redirect_to subscription_path, alert: "No billing account found."
      return
    end

    portal_session = Stripe::BillingPortal::Session.create(
      customer: subscription.stripe_customer_id,
      return_url: subscription_url
    )

    redirect_to portal_session.url, allow_other_host: true
  end

  private

  def find_or_create_subscription
    Current.user.subscription || Current.user.create_subscription!(
      stripe_customer_id: create_stripe_customer.id,
      plan: :free,
      status: :incomplete
    )
  end

  def create_stripe_customer
    Stripe::Customer.create(email: Current.user.email)
  end
end
