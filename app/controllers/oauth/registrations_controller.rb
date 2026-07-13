# frozen_string_literal: true

module Oauth
  class RegistrationsController < ActionController::API
    rate_limit to: 10, within: 1.hour, by: -> { request.remote_ip }, with: -> { head :too_many_requests }
    wrap_parameters false

    # POST /oauth/register (RFC 7591 Dynamic Client Registration)
    def create
      redirect_uris = registration_params[:redirect_uris]

      if redirect_uris.blank? || !redirect_uris.is_a?(Array) || redirect_uris.empty?
        return render json: { error: "invalid_client_metadata", error_description: "redirect_uris is required" }, status: :bad_request
      end

      client_name = registration_params[:client_name].presence || "OAuth Client"

      if client_name.length > 255
        return render json: { error: "invalid_client_metadata", error_description: "client_name must be 255 characters or fewer" }, status: :bad_request
      end

      if redirect_uris.length > 10
        return render json: { error: "invalid_client_metadata", error_description: "Maximum 10 redirect_uris allowed" }, status: :bad_request
      end

      redirect_uris.each do |uri|
        parsed = URI.parse(uri)
        unless parsed.host&.in?(%w[localhost 127.0.0.1 ::1])
          return render json: { error: "invalid_client_metadata", error_description: "Only localhost redirect URIs are allowed" }, status: :bad_request
        end
      end

      application = Doorkeeper::Application.create!(
        name: client_name,
        redirect_uri: redirect_uris.join("\n"),
        scopes: "mcp_read mcp_write",
        confidential: false,
        dynamic: true
      )

      render json: {
        client_id: application.uid,
        client_name: application.name,
        redirect_uris: redirect_uris,
        grant_types: [ "authorization_code", ScreenoteOauth::DeviceCodeGrant::GRANT_TYPE, "refresh_token" ],
        token_endpoint_auth_method: "none",
        response_types: [ "code" ],
        client_id_issued_at: application.created_at.to_i,
        client_secret_expires_at: 0
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
