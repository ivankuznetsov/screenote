# frozen_string_literal: true

require Rails.root.join("lib/screenote_oauth/device_code_grant")

Doorkeeper::GrantFlow.register(
  :device_code,
  grant_type_matches: ScreenoteOauth::DeviceCodeGrant::GRANT_TYPE,
  grant_type_strategy: ScreenoteOauth::DeviceCodeGrant::Strategy
)

Doorkeeper.configure do
  orm :active_record

  # Bearer credentials and confidential-client secrets are one-way hashed at
  # rest. The release migration performs a stopped-process conversion of every
  # existing secret, so accepting plaintext as a fallback would reopen the
  # exposure this boundary is intended to close.
  hash_token_secrets
  hash_application_secrets

  # Persist server-selected authority through authorization codes, device-code
  # exchange, and refresh rotation.
  custom_access_token_attributes %i[principal_kind project_id]

  # Authenticate the resource owner (user) via rails_simple_auth.
  # If the user isn't signed in, redirect to the login page.
  resource_owner_authenticator do
    Current.user || begin
      # Store the full OAuth authorize URL so the user returns here after login
      session[:return_to] = request.fullpath
      redirect_to(new_session_path, alert: "Please sign in to authorize this application.")
    end
  end

  # OAuth 2.1 mandates PKCE for all public clients
  force_pkce

  default_scopes :mcp_read
  optional_scopes :mcp_write

  # MCP clients (e.g. Claude Code) don't implement refresh token flows,
  # so access tokens need a long lifetime to avoid breaking connections.
  access_token_expires_in 1.year
  use_refresh_token

  # RFC 8252 native clients use exact loopback IP literals with ephemeral ports.
  force_ssl_in_redirect_uri { |uri| !%w[127.0.0.1 ::1].include?(uri.hostname) }

  # Browser-based PKCE remains the default; RFC 8628 supports headless clients.
  grant_flows %w[authorization_code device_code]

  # Consent is never skipped: the resource owner must be able to choose user
  # versus project authority for every grant.
end

Rails.application.config.to_prepare do
  [ Doorkeeper::AccessGrant, Doorkeeper::AccessToken ].each do |model|
    model.include(OauthPrincipalRecord) unless model < OauthPrincipalRecord
  end
end
