# frozen_string_literal: true

require "openssl"

module AuthenticationLinks
  class Resolver
    STATUSES = %i[valid invalid expired already_used superseded cancelled].freeze

    class Result
      attr_reader :status, :token

      def initialize(status:, token: nil)
        raise ArgumentError, "invalid authentication-link resolution status" unless STATUSES.include?(status)

        @status = status
        @token = token
        freeze
      end

      def valid?
        status == :valid
      end

      def inspect
        "#<#{self.class.name} status=#{status.inspect} token_id=#{token&.id.inspect}>"
      end

      alias_method :to_s, :inspect

      def as_json(*)
        { "status" => status.to_s, "token_id" => token&.id }
      end
    end

    def initialize(keyring:, clock: -> { Time.current })
      @deriver = Deriver.new(keyring: keyring)
      @clock = clock
    end

    def resolve(credential:, expected_purpose:)
      purpose = canonical_purpose(expected_purpose)
      decoded = decode(credential)
      return invalid unless purpose && decoded

      token = AuthenticationToken.find_by(token_digest: decoded.digest)
      return invalid unless token && token.purpose == purpose
      return invalid unless verified?(token, decoded: decoded)

      lifecycle_result(token)
    rescue Keyring::MissingKey, Deriver::Error
      invalid
    end

    alias_method :call, :resolve

    def revalidate(token_id:, expected_purpose:)
      purpose = canonical_purpose(expected_purpose)
      return invalid unless purpose && token_id.is_a?(Integer) && token_id.positive?

      token = AuthenticationToken.find_by(id: token_id)
      return invalid unless token && token.purpose == purpose
      return invalid unless verified?(token)

      lifecycle_result(token)
    rescue Keyring::MissingKey, Deriver::Error
      invalid
    end

    private

    def canonical_purpose(value)
      value = value.to_s if value.is_a?(Symbol)
      value if value.is_a?(String) && AuthenticationToken.purposes.key?(value)
    end

    def decode(credential)
      case credential
      when Presentation::Decoded
        credential if credential.secret_bytes.bytesize == Presentation::SECRET_BYTES
      when String
        if credential.bytesize == Presentation::SECRET_BYTES
          Presentation::Decoded.new(credential)
        elsif credential.start_with?("#")
          Presentation.decode_fragment(credential)
        else
          Presentation.decode(credential)
        end
      end
    rescue Presentation::Error
      nil
    end

    def verified?(token, decoded: nil)
      return false unless token.valid?

      derived = derive(token)
      digest_matches = secure_equal?(derived.digest, token.token_digest)
      return digest_matches unless decoded

      supplied_digest_matches = decoded.matches_digest?(token.token_digest)
      secret_matches = secure_equal?(derived.secret_bytes, decoded.secret_bytes)
      digest_matches && supplied_digest_matches && secret_matches
    end

    def derive(token)
      @deriver.derive(
        purpose: token.purpose,
        subject_type: token.subject_type,
        subject_id: token.subject_id,
        generation: token.generation,
        derivation_id: token.derivation_id,
        expires_at: token.expires_at,
        key_id: token.derivation_key_id
      )
    end

    def lifecycle_result(token)
      now = current_time
      return invalid unless now

      status = if token.outstanding?
        token.expires_at <= now ? :expired : :valid
      else
        {
          "consumed" => :already_used,
          "superseded" => :superseded,
          "cancelled" => :cancelled
        }.fetch(token.state)
      end

      Result.new(status: status, token: token)
    end

    def current_time
      value = @clock.call
      value = value.to_time if value.respond_to?(:to_time)
      value if value.is_a?(Time)
    end

    def secure_equal?(actual, expected)
      actual.is_a?(String) && expected.is_a?(String) &&
        actual.bytesize == expected.bytesize &&
        OpenSSL.fixed_length_secure_compare(actual, expected)
    end

    def invalid
      Result.new(status: :invalid)
    end
  end
end
