# frozen_string_literal: true

class StripeWebhooksController < ActionController::Base
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

    Rails.logger.info("Stripe webhook received: type=#{event.type} id=#{event.id}")

    case event.type
    when "checkout.session.completed"
      handle_checkout_completed(event.data.object)
    when "customer.subscription.updated"
      handle_subscription_updated(event.data.object)
    when "customer.subscription.deleted"
      handle_subscription_deleted(event.data.object)
    else
      Rails.logger.info("Stripe webhook: ignoring unhandled event type '#{event.type}'")
    end

    head :ok
  rescue Stripe::StripeError, ActiveRecord::RecordInvalid => e
    Honeybadger.notify(e, context: { event_type: event&.type, event_id: event&.id })
    head :internal_server_error
  end

  private

  def handle_checkout_completed(session)
    subscription = find_subscription(session.customer, "checkout.session.completed")
    return unless subscription
    return unless session.subscription

    stripe_sub = Stripe::Subscription.retrieve(session.subscription)
    subscription.update!(
      stripe_subscription_id: stripe_sub.id,
      plan: :pro,
      status: stripe_sub.status == "active" ? :active : :incomplete,
      current_period_end: Time.at(stripe_sub.current_period_end).utc
    )
  end

  def handle_subscription_updated(stripe_sub)
    subscription = find_subscription(stripe_sub.customer, "customer.subscription.updated")
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
    subscription = find_subscription(stripe_sub.customer, "customer.subscription.deleted")
    return unless subscription

    subscription.update!(plan: :free, status: :canceled, stripe_subscription_id: nil)
  end

  def find_subscription(stripe_customer_id, event_type)
    subscription = Subscription.find_by(stripe_customer_id: stripe_customer_id)
    unless subscription
      Honeybadger.notify("Stripe webhook: no subscription found", context: {
        stripe_customer_id: stripe_customer_id,
        event_type: event_type
      })
    end
    subscription
  end
end
