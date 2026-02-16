# frozen_string_literal: true

class OauthMetadataController < ApplicationController
  skip_before_action :require_authentication

  # GET /.well-known/oauth-protected-resource (RFC 9728)
  def protected_resource
    render json: {
      resource: mcp_resource_url,
      authorization_servers: [ root_url.chomp("/") ],
      bearer_methods_supported: [ "header" ]
    }
  end

  # GET /.well-known/oauth-authorization-server (RFC 8414)
  def authorization_server
    base = root_url.chomp("/")
    render json: {
      issuer: base,
      authorization_endpoint: "#{base}/oauth/authorize",
      token_endpoint: "#{base}/oauth/token",
      registration_endpoint: "#{base}/oauth/register",
      response_types_supported: [ "code" ],
      grant_types_supported: [ "authorization_code", "refresh_token" ],
      code_challenge_methods_supported: [ "S256" ],
      token_endpoint_auth_methods_supported: [ "none", "client_secret_post" ],
      scopes_supported: [ "mcp_read", "mcp_write" ],
      revocation_endpoint: "#{base}/oauth/revoke"
    }
  end

  private

  def mcp_resource_url
    "#{root_url.chomp("/")}/mcp"
  end
end
