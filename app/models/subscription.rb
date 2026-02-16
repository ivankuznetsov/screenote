# frozen_string_literal: true

class Subscription < ApplicationRecord
  belongs_to :user

  enum :plan, { free: 0, pro: 1 }
  enum :status, { incomplete: 0, active: 1, past_due: 2, canceled: 3 }, prefix: true

  validates :stripe_customer_id, presence: true, uniqueness: true
  validates :user_id, uniqueness: true
  validates :stripe_subscription_id, presence: true, if: -> { pro? && status_active? }
  validates :current_period_end, presence: true, if: -> { pro? && status_active? }

  FREE_PROJECT_LIMIT = 1
  FREE_MEMBER_LIMIT = 1
  PRO_PRICE_CENTS = 1000

  def active_pro?
    pro? && status_active?
  end
end
