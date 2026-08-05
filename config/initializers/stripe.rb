# frozen_string_literal: true

deployment = Screenote::Deployment.current

Stripe.api_key = deployment.billing? ? ENV["STRIPE_SECRET_KEY"] : nil
