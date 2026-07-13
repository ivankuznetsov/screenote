# frozen_string_literal: true

module ScreenoteOauth
  module DeviceCodeGrant
    GRANT_TYPE = "urn:ietf:params:oauth:grant-type:device_code"

    class ErrorResponse < Doorkeeper::OAuth::ErrorResponse
      def headers
        super.merge("Pragma" => "no-cache")
      end
    end

    class Strategy < Doorkeeper::Request::Strategy
      delegate :client, :parameters, to: :server

      def authorize
        return error_response(:invalid_client) unless client
        return error_response(:invalid_request) if parameters[:device_code].blank?

        grant = OauthDeviceGrant.find_by_plaintext_device_code(parameters[:device_code])
        return error_response(:invalid_grant) unless grant
        return error_response(:invalid_grant) unless grant.application_id == client.application.id

        exchange(grant)
      rescue ActiveRecord::RecordNotFound
        error_response(:invalid_grant)
      end

      private

      def exchange(grant)
        response = nil

        grant.with_lock do
          response =
            if grant.expired?
              consume_with_error(grant, :expired_token)
            elsif grant.denied?
              consume_with_error(grant, :access_denied)
            elsif grant.approved?
              issue_token(grant)
            else
              pending_response(grant)
            end
        end

        response
      end

      def consume_with_error(grant, error)
        grant.destroy!
        error_response(error)
      end

      def pending_response(grant)
        now = Time.current

        if grant.last_polled_at && now < grant.last_polled_at + grant.polling_interval.seconds
          grant.update!(last_polled_at: now, polling_interval: grant.polling_interval + 5)
          error_response(:slow_down)
        else
          grant.update!(last_polled_at: now)
          error_response(:authorization_pending)
        end
      end

      def issue_token(grant)
        context = Doorkeeper::OAuth::Authorization::Token.build_context(
          client,
          GRANT_TYPE,
          grant.scopes,
          grant.resource_owner_id
        )
        token = Doorkeeper.config.access_token_model.create_for(
          application: grant.application,
          resource_owner: grant.resource_owner_id,
          scopes: grant.scopes,
          expires_in: Doorkeeper::OAuth::Authorization::Token.access_token_expires_in(Doorkeeper.config, context),
          use_refresh_token: Doorkeeper::OAuth::Authorization::Token.refresh_token_enabled?(Doorkeeper.config, context)
        )

        grant.destroy!
        Doorkeeper::OAuth::TokenResponse.new(token)
      end

      def error_response(name)
        ErrorResponse.new(name: name)
      end
    end
  end
end
