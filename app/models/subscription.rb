# frozen_string_literal: true

class Subscription < ApplicationRecord
  belongs_to :user

  enum :plan, { free: 0, pro: 1 }
  enum :status, { incomplete: 0, active: 1, past_due: 2, canceled: 3 }, prefix: true

  validates :stripe_customer_id, presence: true, uniqueness: true
  validates :user_id, uniqueness: true

  FREE_PROJECT_LIMIT = 1
  FREE_MEMBER_LIMIT = 1
  PRO_PRICE_CENTS = 1000

  def project_limit
    pro? ? Float::INFINITY : FREE_PROJECT_LIMIT
  end

  def member_limit
    pro? ? Float::INFINITY : FREE_MEMBER_LIMIT
  end

  def active_pro?
    pro? && status_active?
  end

  def can_create_project?(current_count)
    pro? && status_active? || current_count < FREE_PROJECT_LIMIT
  end

  def can_invite_member?(current_member_count)
    pro? && status_active? || current_member_count < FREE_MEMBER_LIMIT
  end
end
