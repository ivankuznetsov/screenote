# frozen_string_literal: true

module Api
  class BearerAuthenticator
    Result = Data.define(:api_key, :oauth_token, :user) do
      def api_key?
        api_key.present?
      end

      def oauth?
        oauth_token.present?
      end
    end

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

      api_key.touch_last_used!
      Result.new(api_key: api_key, oauth_token: nil, user: nil)
    end

    def authenticate_oauth_token
      access_token = Doorkeeper::AccessToken.by_token(token)
      return nil unless access_token
      return nil if access_token.revoked? || access_token.expired?

      user = User.find_by(id: access_token.resource_owner_id)
      return nil unless user

      Result.new(api_key: nil, oauth_token: access_token, user: user)
    end
  end
end
