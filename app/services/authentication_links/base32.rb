# frozen_string_literal: true

require "openssl"

module AuthenticationLinks
  module Base32
    ALPHABET = "ABCDEFGHIJKLMNOPQRSTUVWXYZ234567"
    LOOKUP = ALPHABET.each_char.with_index.to_h.freeze

    class InvalidEncoding < ArgumentError; end

    module_function

    def encode(bytes)
      unless bytes.is_a?(String)
        raise InvalidEncoding, "Base32 input must be bytes"
      end

      buffer = 0
      bits = 0
      encoded = +""

      bytes.each_byte do |byte|
        buffer = (buffer << 8) | byte
        bits += 8

        while bits >= 5
          bits -= 5
          encoded << ALPHABET[(buffer >> bits) & 31]
        end
        buffer &= (1 << bits) - 1 if bits.positive?
      end

      encoded << ALPHABET[(buffer << (5 - bits)) & 31] if bits.positive?
      encoded
    end

    def decode(encoded)
      unless encoded.is_a?(String) && encoded.ascii_only? && encoded.match?(/\A[A-Z2-7]+\z/)
        raise InvalidEncoding, "Base32 input is invalid"
      end

      buffer = 0
      bits = 0
      decoded = []

      encoded.each_char do |character|
        buffer = (buffer << 5) | LOOKUP.fetch(character)
        bits += 5

        while bits >= 8
          bits -= 8
          decoded << ((buffer >> bits) & 255)
        end
        buffer &= (1 << bits) - 1 if bits.positive?
      end

      raise InvalidEncoding, "Base32 input has nonzero padding bits" unless buffer.zero?

      bytes = decoded.pack("C*").b
      canonical = encode(bytes)
      unless canonical.bytesize == encoded.bytesize && OpenSSL.fixed_length_secure_compare(canonical, encoded)
        raise InvalidEncoding, "Base32 input is not canonical"
      end
      bytes
    end

    def group(encoded)
      encoded.scan(/.{4}/).join("-")
    end
  end
end
