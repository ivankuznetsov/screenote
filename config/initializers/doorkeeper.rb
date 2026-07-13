# frozen_string_literal: true

require Rails.root.join("lib/screenote_oauth/device_code_grant")

Doorkeeper::GrantFlow.register(
  :device_code,
  grant_type_matches: ScreenoteOauth::DeviceCodeGrant::GRANT_TYPE,
  grant_type_strategy: ScreenoteOauth::DeviceCodeGrant::Strategy
)

Doorkeeper.configure do
  orm :active_record

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

  # Allow HTTP redirect URIs for localhost (RFC 8252 loopback redirect).
  # Native OAuth clients like Claude Code use http://localhost callbacks.
  force_ssl_in_redirect_uri { |uri| !uri.host.in?(%w[localhost 127.0.0.1]) }

  # Browser-based PKCE remains the default; RFC 8628 supports headless clients.
  grant_flows %w[authorization_code device_code]

  # Skip consent screen for previously-authorized client+scope combinations
  skip_authorization do |resource_owner, client|
    Doorkeeper::AccessToken.matching_token_for(client, resource_owner, client.scopes).present?
  end
end
