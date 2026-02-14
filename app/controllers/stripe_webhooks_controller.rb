# frozen_string_literal: true

class StripeWebhooksController < ApplicationController
  skip_before_action :require_authentication
  skip_forgery_protection

  def create
    payload = request.body.read
    sig_header = request.env["HTTP_STRIPE_SIGNATURE"]

    begin
      event = Stripe::Webhook.construct_event(payload, sig_header, ENV.fetch("STRIPE_WEBHOOK_SECRET"))
    rescue JSON::ParserError, Stripe::SignatureVerificationError => e
      Honeybadger.notify(e)
      head :bad_request
      return
    end

    case event.type
    when "checkout.session.completed"
      handle_checkout_completed(event.data.object)
    when "customer.subscription.updated"
      handle_subscription_updated(event.data.object)
    when "customer.subscription.deleted"
      handle_subscription_deleted(event.data.object)
    end

    head :ok
  end

  private

  def handle_checkout_completed(session)
    subscription = Subscription.find_by(stripe_customer_id: session.customer)
    return unless subscription

    stripe_sub = Stripe::Subscription.retrieve(session.subscription)
    subscription.update!(
      stripe_subscription_id: stripe_sub.id,
      plan: :pro,
      status: stripe_sub.status == "active" ? :active : :incomplete,
      current_period_end: Time.at(stripe_sub.current_period_end).utc
    )
  end

  def handle_subscription_updated(stripe_sub)
    subscription = Subscription.find_by(stripe_customer_id: stripe_sub.customer)
    return unless subscription

    status = case stripe_sub.status
    when "active" then :active
    when "past_due" then :past_due
    when "canceled", "unpaid" then :canceled
    else :incomplete
    end

    subscription.update!(
      status: status,
      current_period_end: Time.at(stripe_sub.current_period_end).utc
    )
  end

  def handle_subscription_deleted(stripe_sub)
    subscription = Subscription.find_by(stripe_customer_id: stripe_sub.customer)
    return unless subscription

    subscription.update!(plan: :free, status: :canceled, stripe_subscription_id: nil)
  end
end
