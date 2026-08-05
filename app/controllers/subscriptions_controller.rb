# frozen_string_literal: true

class SubscriptionsController < ApplicationController
  rescue_from Stripe::StripeError do |e|
    Screenote::Monitoring.notify(e)
    redirect_to subscription_path, alert: "We couldn't connect to our payment provider. Please try again shortly."
  end

  def show
    @subscription = Current.user.subscription
    @checkout_status = params[:status]
  end

  def checkout
    if Current.user.pro?
      redirect_to subscription_path, notice: "You're already on the Pro plan."
      return
    end

    if Current.user.subscription&.stripe_subscription_id.present?
      redirect_to subscription_path, alert: "You already have a subscription. Use the billing portal to manage it."
      return
    end

    subscription = find_or_create_subscription

    checkout_session = Stripe::Checkout::Session.create(
      customer: subscription.stripe_customer_id,
      mode: "subscription",
      line_items: [ { price: ENV.fetch("STRIPE_PRO_PRICE_ID"), quantity: 1 } ],
      success_url: canonical_subscription_url(status: "success"),
      cancel_url: canonical_subscription_url(status: "canceled")
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
      return_url: canonical_subscription_url
    )

    redirect_to portal_session.url, allow_other_host: true
  end

  private

  def canonical_subscription_url(**options)
    subscription_url(Screenote::Deployment.current.url_options.merge(options))
  end

  def find_or_create_subscription
    Current.user.with_lock do
      Current.user.subscription || create_subscription_with_stripe_customer
    end
  end

  def create_subscription_with_stripe_customer
    stripe_customer = Stripe::Customer.create(email: Current.user.email)
    Current.user.create_subscription!(
      stripe_customer_id: stripe_customer.id,
      plan: :free,
      status: :incomplete
    )
  rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotUnique
    Current.user.reload.subscription || raise
  end
end
