# frozen_string_literal: true

require "base64"
require "digest"
require "openssl"
require "uri"

module AuthenticationLinks
  class Presentation
    VERSION = "v1"
    SECRET_BYTES = 32
    BASE64_LENGTH = 43
    BASE32_LENGTH = 52
    PURPOSE_PATTERN = /\A[a-z][a-z0-9_]{0,63}\z/
    FRAGMENT_PATTERN = /\Av1\.([A-Za-z0-9_-]{43})\z/
    MANUAL_CODE_PATTERN = /\Av1\.([A-Z2-7]{4}(?:-[A-Z2-7]{4}){12})\z/

    class Error < StandardError; end
    class InvalidEncoding < Error; end
    class InvalidOrigin < Error; end
    class InvalidPurpose < Error; end

    class Decoded
      attr_reader :digest

      def initialize(secret_bytes)
        @secret_bytes = secret_bytes.b.dup.freeze
        @digest = Digest::SHA256.hexdigest(@secret_bytes).freeze
        freeze
      end

      def secret_bytes
        @secret_bytes.dup
      end

      def matches_digest?(expected_digest)
        expected_digest.is_a?(String) &&
          expected_digest.bytesize == digest.bytesize &&
          OpenSSL.fixed_length_secure_compare(digest, expected_digest)
      end

      def inspect
        "#<#{self.class.name} [FILTERED]>"
      end

      alias_method :to_s, :inspect

      def as_json(*)
        "[FILTERED]"
      end
    end

    class << self
      def decode(value)
        unless value.is_a?(String) && value.ascii_only?
          raise InvalidEncoding, "authentication-link presentation is invalid"
        end

        case value
        when FRAGMENT_PATTERN
          decode_base64(Regexp.last_match(1))
        when MANUAL_CODE_PATTERN
          decode_base32(Regexp.last_match(1))
        else
          raise InvalidEncoding, "authentication-link presentation is invalid"
        end
      end

      def decode_fragment(fragment)
        unless fragment.is_a?(String) && fragment.ascii_only? && fragment.start_with?("#")
          raise InvalidEncoding, "authentication-link fragment is invalid"
        end

        value = fragment.delete_prefix("#")
        match = FRAGMENT_PATTERN.match(value)
        raise InvalidEncoding, "authentication-link fragment is invalid" unless match

        decode_base64(match[1])
      end

      private

      def decode_base64(encoded)
        bytes = Base64.strict_decode64(encoded.tr("-_", "+/") + "=").b
        Decoded.new(bytes)
      rescue ArgumentError
        raise InvalidEncoding, "authentication-link fragment is invalid"
      end

      def decode_base32(grouped)
        encoded = grouped.delete("-")
        bytes = Base32.decode(encoded)
        Decoded.new(bytes)
      rescue Base32::InvalidEncoding
        raise InvalidEncoding, "authentication-link manual code is invalid"
      end
    end

    attr_reader :origin, :purpose

    def initialize(origin:, purpose:, secret_bytes:)
      @origin = canonical_origin(origin).freeze
      @purpose = canonical_purpose(purpose).freeze
      @secret_bytes = canonical_secret(secret_bytes)
      freeze
    end

    def fragment
      "#{VERSION}.#{Base64.urlsafe_encode64(@secret_bytes, padding: false)}"
    end

    def manual_code
      "#{VERSION}.#{Base32.group(Base32.encode(@secret_bytes))}"
    end

    def url
      "#{origin}/authentication-links/#{purpose}##{fragment}"
    end

    def inspect
      "#<#{self.class.name} [FILTERED]>"
    end

    alias_method :to_s, :inspect

    def as_json(*)
      "[FILTERED]"
    end

    private

    def canonical_origin(value)
      raise InvalidOrigin, "authentication-link origin is invalid" unless value.is_a?(String)

      uri = URI.parse(value)
      valid_path = uri.path.nil? || uri.path.empty? || uri.path == "/"
      valid = uri.is_a?(URI::HTTP) && %w[http https].include?(uri.scheme) &&
        !uri.host.to_s.empty? && uri.userinfo.nil? && valid_path && uri.query.nil? && uri.fragment.nil?
      raise InvalidOrigin, "authentication-link origin is invalid" unless valid

      authority = uri.hostname
      authority = "[#{authority}]" if authority.include?(":")
      authority = "#{authority}:#{uri.port}" unless default_port?(uri)
      "#{uri.scheme}://#{authority}"
    rescue URI::InvalidURIError, URI::InvalidComponentError
      raise InvalidOrigin, "authentication-link origin is invalid"
    end

    def canonical_purpose(value)
      value = value.to_s if value.is_a?(Symbol)
      unless value.is_a?(String) && value.ascii_only? && value.match?(PURPOSE_PATTERN)
        raise InvalidPurpose, "authentication-link purpose is invalid"
      end

      value
    end

    def canonical_secret(value)
      unless value.is_a?(String) && value.bytesize == SECRET_BYTES
        raise InvalidEncoding, "authentication-link credentials must contain exactly 32 bytes"
      end

      value.b.dup.freeze
    end

    def default_port?(uri)
      (uri.scheme == "http" && uri.port == 80) || (uri.scheme == "https" && uri.port == 443)
    end
  end
end
