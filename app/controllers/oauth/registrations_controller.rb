# frozen_string_literal: true

module Oauth
  class RegistrationsController < ApplicationController
    skip_before_action :require_authentication
    skip_before_action :verify_authenticity_token

    # POST /oauth/register (RFC 7591 Dynamic Client Registration)
    def create
      params = registration_params
      redirect_uris = params[:redirect_uris]

      if redirect_uris.blank? || !redirect_uris.is_a?(Array) || redirect_uris.empty?
        return render json: { error: "invalid_client_metadata", error_description: "redirect_uris is required" }, status: :bad_request
      end

      application = Doorkeeper::Application.create!(
        name: params[:client_name].presence || "MCP Client",
        redirect_uri: redirect_uris.join("\n"),
        scopes: "mcp_read mcp_write",
        confidential: false,
        dynamic: true
      )

      render json: {
        client_id: application.uid,
        client_name: application.name,
        redirect_uris: redirect_uris,
        grant_types: [ "authorization_code" ],
        token_endpoint_auth_method: "none",
        response_types: [ "code" ]
      }, status: :created
    rescue ActiveRecord::RecordInvalid => e
      render json: { error: "invalid_client_metadata", error_description: e.message }, status: :bad_request
    end

    private

    def registration_params
      params.permit(:client_name, :token_endpoint_auth_method, redirect_uris: [], grant_types: [])
    end
  end
end
