# frozen_string_literal: true

# OmniAuth provider configuration
# Security: POST-only for OAuth initiation is set by rails_simple_auth gem
Rails.application.config.middleware.use OmniAuth::Builder do
  provider :google_oauth2, ENV.fetch("GOOGLE_CLIENT_ID", nil), ENV.fetch("GOOGLE_CLIENT_SECRET", nil), {
    scope: "email,profile"
  }

  provider :github, ENV.fetch("GITHUB_CLIENT_ID", nil), ENV.fetch("GITHUB_CLIENT_SECRET", nil), {
    scope: "user:email"
  }
end
