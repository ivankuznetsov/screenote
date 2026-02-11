# frozen_string_literal: true

RailsSimpleAuth.configure do |config|
  # Features
  config.magic_link_enabled = true
  config.email_confirmation_enabled = true
  config.enable_oauth(google_oauth2: "Google", github: "GitHub")

  # Token Expiration
  config.magic_link_expiry = 15.minutes
  config.password_reset_expiry = 15.minutes
  config.confirmation_expiry = 24.hours
  config.session_expiry = 30.days

  # Rate Limiting
  config.rate_limits = {
    sign_in: { limit: 5, period: 15.minutes },
    sign_up: { limit: 5, period: 1.hour },
    magic_link: { limit: 3, period: 10.minutes },
    password_reset: { limit: 3, period: 1.hour },
    confirmation: { limit: 3, period: 1.hour }
  }

  # Paths
  config.after_sign_in_path = :root_path
  config.after_sign_out_path = :new_session_path
  config.after_sign_up_path = :root_path
  config.after_confirmation_path = :new_session_path

  # Layout — separate from application to avoid engine namespace issues
  config.layout = "auth"

  # Mailer
  config.mailer_sender = ENV.fetch("MAILER_FROM", "noreply@screenote.app")
  config.mailer_class = "UserMailer"

  # Models
  config.user_class_name = "User"
  config.session_class_name = "Session"

  # Password Requirements
  config.password_minimum_length = 8
end
