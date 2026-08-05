# frozen_string_literal: true

module Oauth
  class TokensController < Doorkeeper::TokensController
    def create
      credential = credential_for_exchange
      return super unless credential

      PrincipalBinding.with_locked_credential(credential) do |valid|
        valid ? super() : render_invalid_principal_binding
      end
    end

    private

    def render_invalid_principal_binding
      response.set_header("Cache-Control", "no-store")
      response.set_header("Pragma", "no-cache")
      render json: { error: "invalid_grant" }, status: :bad_request
    end

    def credential_for_exchange
      case params[:grant_type]
      when "authorization_code"
        Doorkeeper::AccessGrant.by_token(params[:code])
      when "refresh_token"
        Doorkeeper::AccessToken.by_refresh_token(params[:refresh_token])
      end
    end

    def after_successful_authorization(context)
      super
      application = context.auth.respond_to?(:token) ? context.auth.token&.application : nil
      DynamicClientRegistration.mark_used!(application)
    end
  end
end
