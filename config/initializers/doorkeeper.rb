# frozen_string_literal: true

Doorkeeper.configure do
  orm :active_record

  # Authenticate the resource owner (user) via rails_simple_auth.
  # If the user isn't signed in, redirect to the login page.
  resource_owner_authenticator do
    Current.user || redirect_to(new_session_path, alert: "Please sign in to authorize this application.")
  end

  # OAuth 2.1 mandates PKCE for all public clients
  force_pkce

  default_scopes :mcp_read
  optional_scopes :mcp_write

  access_token_expires_in 1.hour
  use_refresh_token

  # Allow HTTP redirect URIs for localhost (needed for local MCP clients)
  force_ssl_in_redirect_uri !Rails.env.local?

  # Only authorization_code grant flow (OAuth 2.1)
  grant_flows %w[authorization_code]

  # Store project_id on access tokens and grants
  custom_access_token_attributes [ :project_id ]

  # Allow public (non-confidential) clients created by DCR
  allow_token_introspection false

  # Skip authorization for previously authorized clients+scopes
  skip_authorization do |_resource_owner, _client|
    false
  end

  # Use the resource owner's ID (User#id) for the resource_owner_id column
  resource_owner_from_credentials do |_routes|
    nil # We don't support password grant
  end
end
