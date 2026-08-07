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
        return exchange_approved(grant) if grant.approved?

        response = nil
        approved_while_waiting = false

        grant.with_lock do
          if grant.approved?
            # Approval locks authority before this credential. Release this
            # lock and retry in that same order rather than inverting it.
            approved_while_waiting = true
          else
            response = exchange_locked(grant)
          end
        end

        approved_while_waiting ? exchange_approved(grant) : response
      end

      def exchange_approved(grant)
        Oauth::PrincipalBinding.with_locked_credential(grant) do |valid|
          valid ? exchange_locked(grant) : consume_with_error(grant, :invalid_grant)
        end
      end

      def exchange_locked(grant)
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
          use_refresh_token: Doorkeeper::OAuth::Authorization::Token.refresh_token_enabled?(Doorkeeper.config, context),
          principal_kind: grant.principal_kind,
          project_id: grant.project_id
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
