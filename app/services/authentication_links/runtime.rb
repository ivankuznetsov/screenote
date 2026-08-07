# frozen_string_literal: true

require "base64"
require "json"
require "openssl"

module AuthenticationLinks
  class Runtime
    PRIOR_KEYS_ENV = "SCREENOTE_AUTHENTICATION_LINK_PRIOR_KEYS"
    MAX_PRIOR_KEYS_BYTES = 8.kilobytes
    MAX_PRIOR_KEYS = 16
    ENCODED_KEY_PATTERN = /\A[A-Za-z0-9_-]{43}\z/

    class ConfigurationError < StandardError; end

    class << self
      def keyring
        @keyring ||= build(
          secret_key_base: Rails.application.secret_key_base,
          encoded_prior_keys: ENV[PRIOR_KEYS_ENV]
        )
      end

      def origin
        Screenote::Deployment.current.base_url
      end

      def build(secret_key_base:, encoded_prior_keys: nil)
        Keyring.new(
          secret_key_base: secret_key_base,
          prior_keys: decode_prior_keys(encoded_prior_keys)
        )
      rescue Keyring::Error, JSON::ParserError, ArgumentError, TypeError
        raise ConfigurationError, "authentication-link key configuration is invalid"
      end

      # Tests and application reload hooks may clear the immutable cached
      # keyring. Request code must never rotate keys by mutating this object.
      def reset!
        remove_instance_variable(:@keyring) if instance_variable_defined?(:@keyring)
      end

      private

      def decode_prior_keys(encoded)
        return {} if encoded.blank?
        raise ConfigurationError, "authentication-link key configuration is invalid" if encoded.bytesize > MAX_PRIOR_KEYS_BYTES

        parsed = JSON.parse(encoded, allow_duplicate_key: false)
        unless parsed.instance_of?(Hash) && parsed.size <= MAX_PRIOR_KEYS
          raise ConfigurationError, "authentication-link key configuration is invalid"
        end

        parsed.to_h do |key_id, encoded_key|
          [ key_id, decode_key(encoded_key) ]
        end
      end

      def decode_key(encoded_key)
        unless encoded_key.is_a?(String) && encoded_key.match?(ENCODED_KEY_PATTERN)
          raise ConfigurationError, "authentication-link key configuration is invalid"
        end

        Base64.urlsafe_decode64(encoded_key).b
      end
    end
  end
end
