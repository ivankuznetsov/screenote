# frozen_string_literal: true

RailsSimpleAuth.configure do |config|
  deployment = Screenote::Deployment.current

  # Features
  config.magic_link_enabled = deployment.mail?
  config.email_confirmation_enabled = deployment.mail?

  oauth_names = { google_oauth2: "Google", github: "GitHub" }
  enabled_oauth = oauth_names.slice(*deployment.social_oauth_providers)
  config.enable_oauth(enabled_oauth) if enabled_oauth.any?

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
  config.after_sign_in_path = :dashboard_path
  config.after_sign_out_path = :root_path
  config.after_sign_up_path = :dashboard_path
  config.after_confirmation_path = :new_session_path

  # Layout — separate from application to avoid engine namespace issues
  config.layout = "auth"

  # Mailer
  config.mailer_sender = deployment.mail_configuration[:from] || "noreply@localhost"
  config.mailer_class = "UserMailer"

  # Send welcome email on first-ever email confirmation.
  # Dirty tracking: confirmed_at_previously_was is nil only on first confirmation,
  # because the gem calls this callback immediately after confirm! (which calls update).
  config.after_confirmation_callback = lambda do |user, _controller|
    if deployment.mail? && user.confirmed_at_previously_changed? && user.confirmed_at_previously_was.nil?
      UserMailer.welcome(user).deliver_later
    end
  rescue StandardError => e
    if deployment.monitoring?
      Screenote::Monitoring.notify(e, context: { user_id: user.id })
    else
      Rails.logger.error("Welcome email callback failed: #{e.class}")
    end
  end

  # Models
  config.user_class_name = "User"
  config.session_class_name = "Session"

  # Password Requirements
  config.password_minimum_length = 8
end
