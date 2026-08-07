# frozen_string_literal: true

require "base64"
require "digest"
require "openssl"

module AuthenticationLinks
  class Keyring
    KEY_BYTES = 32
    MINIMUM_SECRET_KEY_BASE_BYTES = 32
    KEY_DERIVATION_CONTEXT = "screenote.authentication-links.keyring/v1"
    KEY_ID_CONTEXT = "screenote.authentication-links.key-id/v1\0"

    class Error < StandardError; end
    class InvalidKey < Error; end
    class KeyIdMismatch < Error; end

    class MissingKey < Error
      attr_reader :key_id

      def initialize(key_id)
        @key_id = key_id
        super("authentication-link derivation key is unavailable: #{key_id}")
      end
    end

    class << self
      def fingerprint(key)
        key = normalize_key(key)
        digest = Digest::SHA256.digest(KEY_ID_CONTEXT.b + key)

        "v1.#{Base64.urlsafe_encode64(digest, padding: false)}"
      end

      private

      def normalize_key(key)
        unless key.is_a?(String) && key.bytesize == KEY_BYTES
          raise InvalidKey, "authentication-link derivation keys must contain exactly 32 bytes"
        end

        key.b.dup.freeze
      end
    end

    attr_reader :primary_key_id

    def initialize(secret_key_base:, prior_keys: {})
      primary_key = derive_primary_key(secret_key_base)
      @primary_key_id = self.class.fingerprint(primary_key).freeze
      @keys = { primary_key_id => primary_key }

      add_prior_keys(prior_keys)
      @keys.freeze
      freeze
    end

    def key_ids
      @keys.keys.dup.freeze
    end

    def include?(key_id)
      @keys.key?(key_id)
    end

    def sign(message, key_id: primary_key_id)
      unless message.is_a?(String)
        raise ArgumentError, "authentication-link signing input must be a String"
      end

      key = @keys[key_id]
      raise MissingKey, key_id unless key

      OpenSSL::HMAC.digest("SHA256", key, message.b)
    end

    def inspect
      "#<#{self.class.name} [FILTERED]>"
    end

    alias_method :to_s, :inspect

    def as_json(*)
      "[FILTERED]"
    end

    private

    def derive_primary_key(secret_key_base)
      unless secret_key_base.is_a?(String) && secret_key_base.bytesize >= MINIMUM_SECRET_KEY_BASE_BYTES
        raise InvalidKey, "SECRET_KEY_BASE must contain at least 32 bytes"
      end

      OpenSSL::HMAC.digest("SHA256", secret_key_base.b, KEY_DERIVATION_CONTEXT)
    end

    def add_prior_keys(prior_keys)
      unless prior_keys.is_a?(Hash)
        raise InvalidKey, "prior authentication-link keys must be an id-to-key Hash"
      end

      prior_keys.each do |configured_id, key|
        expected_id = self.class.fingerprint(key)
        normalized_key = key.b.dup.freeze

        unless same_identifier?(configured_id, expected_id)
          raise KeyIdMismatch, "authentication-link derivation key id does not match its fingerprint"
        end
        if @keys.key?(expected_id)
          raise InvalidKey, "authentication-link derivation keys must have unique fingerprints"
        end

        @keys[expected_id.freeze] = normalized_key
      end
    end

    def same_identifier?(configured_id, expected_id)
      configured_id.is_a?(String) &&
        configured_id.bytesize == expected_id.bytesize &&
        OpenSSL.fixed_length_secure_compare(configured_id, expected_id)
    end
  end
end
