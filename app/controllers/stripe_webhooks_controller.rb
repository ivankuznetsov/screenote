# frozen_string_literal: true

# Dispatches Stripe webhook events to the Subscription model. The controller is
# responsible for signature verification, idempotency, row locking, and
# mail side-effects. State transitions live on Subscription.
class StripeWebhooksController < ActionController::Base
  skip_forgery_protection
  before_action :require_billing!

  def create
    payload = request.body.read
    sig_header = request.env["HTTP_STRIPE_SIGNATURE"]

    begin
      event = Stripe::Webhook.construct_event(payload, sig_header, ENV.fetch("STRIPE_WEBHOOK_SECRET"))
    rescue JSON::ParserError, Stripe::SignatureVerificationError => e
      Screenote::Monitoring.notify(e)
      head :bad_request
      return
    end

    Rails.logger.info("Stripe webhook received: type=#{event.type} id=#{event.id}")

    begin
      StripeWebhookEvent.create!(stripe_event_id: event.id)
    rescue ActiveRecord::RecordNotUnique, ActiveRecord::RecordInvalid
      Rails.logger.info("Stripe webhook already processed, skipping: id=#{event.id}")
      head :ok
      return
    end

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

    head :ok unless response.committed? || performed?
  rescue ActiveRecord::RecordInvalid => e
    Screenote::Monitoring.notify(e, context: { event_type: event&.type, event_id: event&.id })
    head :ok # Stop retries for permanent validation failures
  rescue Stripe::StripeError => e
    Screenote::Monitoring.notify(e, context: { event_type: event&.type, event_id: event&.id })
    head :internal_server_error
  end

  private

  def require_billing!
    head :not_found unless Screenote::Deployment.current.billing?
  end

  def handle_checkout_completed(session)
    subscription = find_subscription(session[:customer], "checkout.session.completed")
    return head(:service_unavailable) unless subscription
    return unless session[:subscription]

    stripe_sub = Stripe::Subscription.retrieve(session[:subscription])
    subscription.with_lock { subscription.apply_stripe_checkout(stripe_sub) }
  end

  def handle_subscription_updated(stripe_sub)
    subscription = find_subscription(stripe_sub[:customer], "customer.subscription.updated")
    return head(:service_unavailable) unless subscription

    result = subscription.with_lock { subscription.apply_stripe_update(stripe_sub) }
    notify_new_pro_subscriber(subscription) if result == :activated
  end

  def handle_subscription_deleted(stripe_sub)
    subscription = find_subscription(stripe_sub[:customer], "customer.subscription.deleted")
    return head(:service_unavailable) unless subscription

    subscription.with_lock { subscription.apply_stripe_deletion(stripe_sub[:id]) }
  end

  def notify_new_pro_subscriber(subscription)
    AdminMailer.new_pro_subscriber(subscription.user).deliver_later
  rescue StandardError => e
    Screenote::Monitoring.notify(e, context: { user_id: subscription.user_id })
  end

  def find_subscription(stripe_customer_id, event_type)
    subscription = Subscription.find_by(stripe_customer_id: stripe_customer_id)
    unless subscription
      Screenote::Monitoring.notify("Stripe webhook: no subscription found", context: {
        stripe_customer_id: stripe_customer_id,
        event_type: event_type
      })
    end
    subscription
  end
end
