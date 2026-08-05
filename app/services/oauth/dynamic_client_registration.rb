# frozen_string_literal: true

require "digest"
require "uri"

module Oauth
  class DynamicClientRegistration
    MAX_REDIRECT_URIS = 10
    MAX_REDIRECT_URI_BYTES = 2_048
    MAX_DYNAMIC_CLIENTS = 10_000
    UNUSED_RETENTION = 24.hours
    CAPACITY_LOCK = Mutex.new
    SUPPORTED_GRANT_TYPES = [
      "authorization_code",
      ScreenoteOauth::DeviceCodeGrant::GRANT_TYPE,
      "refresh_token"
    ].freeze

    Result = Data.define(:application, :created)

    class InvalidMetadata < StandardError; end
    class CapacityExceeded < StandardError; end

    class << self
      def call(client_name:, redirect_uris:, token_endpoint_auth_method: nil, grant_types: nil)
        new(
          client_name: client_name,
          redirect_uris: redirect_uris,
          token_endpoint_auth_method: token_endpoint_auth_method,
          grant_types: grant_types
        ).call
      end

      def cleanup_unused!(before: UNUSED_RETENTION.ago)
        deleted = 0
        cleanup_candidates(before: before).find_each do |application|
          application.with_lock do
            next if active_credential?(application)

            application.destroy!
            deleted += 1
          end
        end
        deleted
      end

      def mark_used!(application)
        return unless application&.dynamic?

        application.update_column(:last_used_at, Time.current)
      end

      def maximum_dynamic_clients
        MAX_DYNAMIC_CLIENTS
      end

      private

      def cleanup_candidates(before:)
        Doorkeeper::Application.where(dynamic: true, created_at: ...before)
          .where("last_used_at IS NULL OR last_used_at < ?", before)
      end

      def active_credential?(application)
        application.access_grants.any?(&:accessible?) ||
          application.access_tokens.any? { |token| !token.revoked? && (token.refresh_token.present? || !token.expired?) } ||
          OauthDeviceGrant.where(application_id: application.id, expires_at: Time.current..).exists?
      end
    end

    def initialize(client_name:, redirect_uris:, token_endpoint_auth_method:, grant_types:)
      @client_name = normalize_name(client_name)
      @redirect_uris = normalize_redirect_uris(redirect_uris)
      validate_client_metadata!(token_endpoint_auth_method, grant_types)
    end

    def call
      fingerprint = registration_fingerprint

      CAPACITY_LOCK.synchronize do
        Doorkeeper::Application.transaction do
          # Every prepared deployment has one Installation row. Locking it makes
          # the global capacity check deterministic across application processes;
          # the process lock also covers development/test before preparation.
          Installation.current&.lock!
          existing = Doorkeeper::Application.lock.find_by(
            dynamic: true,
            registration_fingerprint: fingerprint
          )
          return Result.new(application: existing, created: false) if existing

          self.class.cleanup_unused!
          if Doorkeeper::Application.where(dynamic: true).count >= self.class.maximum_dynamic_clients
            raise CapacityExceeded, "Dynamic client registration capacity has been reached"
          end

          application = Doorkeeper::Application.create!(
            name: client_name,
            redirect_uri: redirect_uris.join("\n"),
            scopes: "mcp_read mcp_write",
            confidential: false,
            dynamic: true,
            registration_fingerprint: fingerprint
          )
          Result.new(application: application, created: true)
        end
      end
    rescue ActiveRecord::RecordNotUnique
      existing = Doorkeeper::Application.find_by!(
        dynamic: true,
        registration_fingerprint: fingerprint
      )
      Result.new(application: existing, created: false)
    end

    private

    attr_reader :client_name, :redirect_uris

    def normalize_name(value)
      name = value.to_s.strip.presence || "OAuth Client"
      raise InvalidMetadata, "client_name must be 255 characters or fewer" if name.length > 255

      name
    end

    def normalize_redirect_uris(values)
      unless values.is_a?(Array) && values.any?
        raise InvalidMetadata, "redirect_uris is required"
      end
      if values.length > MAX_REDIRECT_URIS
        raise InvalidMetadata, "Maximum #{MAX_REDIRECT_URIS} redirect_uris allowed"
      end

      normalized = values.map { |value| normalize_loopback_redirect(value) }
      raise InvalidMetadata, "redirect_uris must be unique" unless normalized.uniq.length == normalized.length

      normalized.sort.freeze
    end

    def normalize_loopback_redirect(value)
      raw = value.to_s
      if raw.empty? || raw.bytesize > MAX_REDIRECT_URI_BYTES || !raw.ascii_only? || raw.match?(/[\\\x00-\x20\x7f]/)
        raise InvalidMetadata, loopback_error
      end

      uri = URI.parse(raw)
      valid = uri.instance_of?(URI::HTTP) && uri.scheme == "http" &&
        uri.userinfo.nil? && uri.fragment.nil? &&
        %w[127.0.0.1 ::1].include?(uri.hostname) && uri.host.present?
      raise InvalidMetadata, loopback_error unless valid

      uri.to_s
    rescue URI::InvalidURIError, URI::InvalidComponentError
      raise InvalidMetadata, loopback_error
    end

    def validate_client_metadata!(token_endpoint_auth_method, grant_types)
      if token_endpoint_auth_method.present? && token_endpoint_auth_method != "none"
        raise InvalidMetadata, "token_endpoint_auth_method must be none"
      end

      return if grant_types.blank?
      unless grant_types.is_a?(Array) && grant_types.all? { |grant_type| SUPPORTED_GRANT_TYPES.include?(grant_type) }
        raise InvalidMetadata, "grant_types contains an unsupported grant"
      end
    end

    def registration_fingerprint
      Digest::SHA256.hexdigest([ client_name, redirect_uris.join("\n") ].join("\0"))
    end

    def loopback_error
      "redirect_uris must use an exact http://127.0.0.1 or http://[::1] loopback address without credentials or fragments"
    end
  end
end
