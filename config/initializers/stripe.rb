# frozen_string_literal: true

Stripe.api_key = ENV.fetch("STRIPE_SECRET_KEY", nil)

if Rails.env.production?
  ENV.fetch("STRIPE_SECRET_KEY")
  ENV.fetch("STRIPE_WEBHOOK_SECRET")
  ENV.fetch("STRIPE_PRO_PRICE_ID")
end
