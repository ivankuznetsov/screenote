# frozen_string_literal: true

# Records every Stripe webhook event we've successfully received so retries
# from Stripe (which fires on any 5xx response) don't re-execute handlers
# and re-trigger side-effects like pro-upgrade emails.
class StripeWebhookEvent < ApplicationRecord
  validates :stripe_event_id, presence: true, uniqueness: true
end
