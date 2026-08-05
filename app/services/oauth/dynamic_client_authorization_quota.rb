# frozen_string_literal: true

require "set"

module Oauth
  class DynamicClientAuthorizationQuota
    MAX_AUTHORIZED_CLIENTS_PER_USER = 25

    class Exceeded < StandardError; end

    class << self
      def authorize(user:, application:)
        return yield unless application.dynamic?

        user.class.transaction do
          AuthorityLock.user!(user)
          active_application_ids = active_dynamic_application_ids(user)

          if !active_application_ids.include?(application.id) &&
              active_application_ids.size >= maximum_authorized_clients_per_user
            raise Exceeded,
              "You can authorize at most #{maximum_authorized_clients_per_user} active dynamic clients. " \
              "Revoke an unused client before authorizing another."
          end

          yield
        end
      end

      private

      def maximum_authorized_clients_per_user
        MAX_AUTHORIZED_CLIENTS_PER_USER
      end

      def active_dynamic_application_ids(user)
        [].to_set.tap do |application_ids|
          active_access_grants(user).find_each do |grant|
            application_ids << grant.application_id if grant.accessible?
          end

          active_access_tokens(user).find_each do |token|
            if token.refresh_token.present? || !token.expired?
              application_ids << token.application_id
            end
          end

          active_device_grants(user).find_each do |grant|
            application_ids << grant.application_id unless grant.expired?
          end
        end
      end

      def active_access_grants(user)
        Doorkeeper::AccessGrant.joins(:application).where(
          resource_owner_id: user.id,
          revoked_at: nil,
          oauth_applications: { dynamic: true }
        )
      end

      def active_access_tokens(user)
        Doorkeeper::AccessToken.joins(:application).where(
          resource_owner_id: user.id,
          revoked_at: nil,
          oauth_applications: { dynamic: true }
        )
      end

      def active_device_grants(user)
        OauthDeviceGrant.joins(:application).where.not(approved_at: nil).where(
          resource_owner_id: user.id,
          denied_at: nil,
          oauth_applications: { dynamic: true }
        )
      end
    end
  end
end
