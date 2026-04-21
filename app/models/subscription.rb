# frozen_string_literal: true

class Subscription < ApplicationRecord
  belongs_to :user

  enum :plan, { free: 0, pro: 1 }
  enum :status, { incomplete: 0, active: 1, past_due: 2, canceled: 3 }

  validates :stripe_customer_id, presence: true, uniqueness: true
  validates :user_id, uniqueness: true
  validates :stripe_subscription_id, presence: true, if: -> { pro? && active? }
  validates :current_period_end, presence: true, if: -> { pro? && active? }

  FREE_PROJECT_LIMIT = 1
  FREE_MEMBER_LIMIT = 1
  PRO_PRICE_CENTS = 1000

  def active_pro?
    pro? && active? && current_period_end.present? && current_period_end > Time.current
  end

  # Apply a Stripe customer.subscription.updated payload. Returns:
  #   :skipped   — event was for a different (non-tracked) Stripe sub on the same customer
  #   :activated — transitioned from non-active-pro into active-pro (caller should send welcome mail)
  #   :updated   — any other successful state mutation
  # Caller is responsible for taking a row lock (with_lock) before invoking.
  def apply_stripe_update(stripe_sub)
    return :skipped if stripe_subscription_id.present? && stripe_subscription_id != stripe_sub[:id]

    was_active_pro = active_pro?
    attrs = { status: self.class.status_from_stripe(stripe_sub[:status]) }
    period_end = self.class.period_end_from_stripe(stripe_sub)
    attrs[:current_period_end] = Time.at(period_end).utc if period_end
    attrs[:plan] = :pro if stripe_subscription_id.present?

    update!(**attrs)
    !was_active_pro && active_pro? ? :activated : :updated
  end

  # Apply a Stripe customer.subscription.deleted payload. Returns :skipped if the
  # event targets a sub we're not tracking, :deleted on a real mutation.
  def apply_stripe_deletion(stripe_sub_id)
    return :skipped unless stripe_subscription_id.present? && stripe_subscription_id == stripe_sub_id

    update!(plan: :free, status: :canceled, stripe_subscription_id: nil)
    :deleted
  end

  # Apply a checkout.session.completed payload. Uses the period_end fetched from
  # Stripe; falls back to 30 days only if Stripe didn't return one.
  def apply_stripe_checkout(stripe_sub)
    period_end = self.class.period_end_from_stripe(stripe_sub)
    update!(
      stripe_subscription_id: stripe_sub[:id],
      plan: :pro,
      status: :active,
      current_period_end: period_end ? Time.at(period_end).utc : 30.days.from_now
    )
  end

  def self.status_from_stripe(stripe_status)
    case stripe_status
    when "active", "trialing" then :active
    when "past_due" then :past_due
    when "canceled", "unpaid" then :canceled
    else :incomplete
    end
  end

  # Stripe API 2026-01-28 moved current_period_end off Subscription onto SubscriptionItem.
  # StripeObject doesn't implement #dig, hence the explicit chain.
  def self.period_end_from_stripe(stripe_sub)
    stripe_sub[:items]&.[](:data)&.first&.[](:current_period_end)
  end
end
