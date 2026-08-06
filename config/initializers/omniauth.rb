# frozen_string_literal: true

deployment = Screenote::Deployment.current
OmniAuth.config.full_host = deployment.base_url

if deployment.social_oauth?
  Rails.application.config.middleware.use OmniAuth::Builder do
    if deployment.social_oauth_providers.include?(:google_oauth2)
      google = deployment.social_oauth_configuration(:google_oauth2)
      provider :google_oauth2, google[:client_id], google[:client_secret], scope: "email,profile"
    end

    if deployment.social_oauth_providers.include?(:github)
      github = deployment.social_oauth_configuration(:github)
      provider :github, github[:client_id], github[:client_secret], scope: "user:email"
    end
  end
end

# rails_simple_auth 1.1 disables OmniAuth's request-phase CSRF validation in a
# later engine initializer. Restore it after every initializer has run and bind
# Rack Protection to Rails' actual encrypted-session CSRF key. OAuth2 strategies
# separately verify callback state.
Rails.application.config.after_initialize do
  OmniAuth.config.allowed_request_methods = %i[post]
  OmniAuth.config.request_validation_phase = OmniAuth::AuthenticityTokenProtection.new(key: :_csrf_token)
end
