# frozen_string_literal: true

require "digest"
require "openssl"

module AuthenticationLinks
  class Deriver
    VERSION = "v1"
    PAYLOAD_DOMAIN = "screenote.authentication-links.credential"
    PURPOSE_PATTERN = /\A[a-z][a-z0-9_]{0,63}\z/
    SUBJECT_TYPE_PATTERN = /\A[A-Z][A-Za-z0-9]*(?:::[A-Z][A-Za-z0-9]*)*\z/
    DERIVATION_ID_PATTERN = /\A[0-9a-f]{64}\z/
    DIGEST_PATTERN = /\A[0-9a-f]{64}\z/

    class Error < StandardError; end
    class InvalidMetadata < Error; end
    class InvalidDigest < Error; end

    class Result
      attr_reader :key_id, :digest
      alias_method :token_digest, :digest

      def initialize(key_id:, secret_bytes:)
        @key_id = key_id.dup.freeze
        @secret_bytes = secret_bytes.b.dup.freeze
        @digest = Digest::SHA256.hexdigest(@secret_bytes).freeze
        freeze
      end

      def secret_bytes
        @secret_bytes.dup
      end

      def inspect
        "#<#{self.class.name} [FILTERED]>"
      end

      alias_method :to_s, :inspect

      def as_json(*)
        "[FILTERED]"
      end
    end

    def initialize(keyring:)
      unless keyring.is_a?(Keyring)
        raise ArgumentError, "keyring must be an AuthenticationLinks::Keyring"
      end

      @keyring = keyring
      freeze
    end

    def derive(purpose:, subject_type:, subject_id:, generation:, derivation_id:, expires_at:, key_id: nil)
      selected_key_id = key_id || @keyring.primary_key_id
      payload = canonical_payload(
        purpose: purpose,
        subject_type: subject_type,
        subject_id: subject_id,
        generation: generation,
        derivation_id: derivation_id,
        expires_at: expires_at
      )

      Result.new(
        key_id: selected_key_id,
        secret_bytes: @keyring.sign(payload, key_id: selected_key_id)
      )
    end

    def matches_digest?(expected_digest:, **metadata)
      unless expected_digest.is_a?(String) && expected_digest.ascii_only? && expected_digest.match?(DIGEST_PATTERN)
        raise InvalidDigest, "authentication-link digest must be 64 lowercase hexadecimal characters"
      end

      actual_digest = derive(**metadata).digest
      OpenSSL.fixed_length_secure_compare(actual_digest, expected_digest)
    end

    def inspect
      "#<#{self.class.name} [FILTERED]>"
    end

    alias_method :to_s, :inspect

    def as_json(*)
      "[FILTERED]"
    end

    private

    def canonical_payload(purpose:, subject_type:, subject_id:, generation:, derivation_id:, expires_at:)
      fields = [
        PAYLOAD_DOMAIN,
        VERSION,
        canonical_purpose(purpose),
        canonical_subject_type(subject_type),
        canonical_positive_integer(subject_id, "subject id"),
        canonical_positive_integer(generation, "generation"),
        canonical_derivation_id(derivation_id),
        canonical_expiry(expires_at)
      ]

      fields.map { |field| [ field.bytesize ].pack("N") + field.b }.join
    end

    def canonical_purpose(value)
      value = value.to_s if value.is_a?(Symbol)
      unless value.is_a?(String) && value.ascii_only? && value.match?(PURPOSE_PATTERN)
        raise InvalidMetadata, "authentication-link purpose is not canonical"
      end

      value
    end

    def canonical_subject_type(value)
      unless value.is_a?(String) && value.ascii_only? && value.match?(SUBJECT_TYPE_PATTERN)
        raise InvalidMetadata, "authentication-link subject type is not canonical"
      end

      value
    end

    def canonical_positive_integer(value, name)
      unless value.is_a?(Integer) && value.positive?
        raise InvalidMetadata, "authentication-link #{name} must be a positive Integer"
      end

      value.to_s
    end

    def canonical_derivation_id(value)
      unless value.is_a?(String) && value.ascii_only? && value.match?(DERIVATION_ID_PATTERN)
        raise InvalidMetadata, "authentication-link derivation id must be 64 lowercase hexadecimal characters"
      end

      value
    end

    def canonical_expiry(value)
      seconds = if value.is_a?(Integer)
        value
      elsif !value.is_a?(String) && value.respond_to?(:to_time)
        value.to_time.to_i
      end

      unless seconds.is_a?(Integer) && seconds.positive?
        raise InvalidMetadata, "authentication-link expiry must be a positive epoch second or time"
      end

      seconds.to_s
    end
  end
end
