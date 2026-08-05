# frozen_string_literal: true

class OauthMetadataController < ApplicationController
  skip_before_action :require_authentication

  # GET /.well-known/oauth-protected-resource (RFC 9728)
  def protected_resource
    render json: {
      resource: "#{base_url}/mcp",
      authorization_servers: [ base_url ],
      bearer_methods_supported: [ "header" ],
      scopes_supported: %w[mcp_read mcp_write]
    }
  end

  # GET /.well-known/oauth-authorization-server (RFC 8414)
  def authorization_server
    render json: {
      issuer: base_url,
      authorization_endpoint: "#{base_url}/oauth/authorize",
      device_authorization_endpoint: "#{base_url}/oauth/authorize_device",
      token_endpoint: "#{base_url}/oauth/token",
      registration_endpoint: "#{base_url}/oauth/register",
      revocation_endpoint: "#{base_url}/oauth/revoke",
      response_types_supported: [ "code" ],
      response_modes_supported: [ "query" ],
      grant_types_supported: [
        "authorization_code",
        ScreenoteOauth::DeviceCodeGrant::GRANT_TYPE,
        "refresh_token"
      ],
      code_challenge_methods_supported: [ "S256" ],
      token_endpoint_auth_methods_supported: %w[none client_secret_post],
      scopes_supported: %w[mcp_read mcp_write],
      client_id_metadata_document_supported: false
    }
  end

  private

  def base_url
    Screenote::Deployment.current.base_url
  end
end
