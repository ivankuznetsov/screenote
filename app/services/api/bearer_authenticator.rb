# frozen_string_literal: true

module Api
  class BearerAuthenticator
    def self.call(token)
      new(token).call
    end

    def initialize(token)
      @token = token
    end

    def call
      return nil if token.blank?

      authenticate_api_key || authenticate_oauth_token
    end

    private

    attr_reader :token

    def authenticate_api_key
      api_key = ApiKey.active.find_by_token(token)
      return nil unless api_key

      principal = AuthenticatedPrincipal.for_api_key(api_key)
      return nil unless principal

      api_key.touch_last_used!
      principal
    end

    def authenticate_oauth_token
      access_token = Doorkeeper::AccessToken.by_token(token)
      return nil unless access_token
      return nil if access_token.revoked? || access_token.expired?

      AuthenticatedPrincipal.for_oauth_token(access_token)
    end
  end
end
