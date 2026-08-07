# frozen_string_literal: true

require "test_helper"

module AuthenticationLinks
  class Base32Test < ActiveSupport::TestCase
    test "round trips arbitrary bytes and groups the canonical representation" do
      bytes = "\x00\xFFscreenote\x10".b
      encoded = Base32.encode(bytes)

      assert_equal bytes, Base32.decode(encoded)
      assert_equal encoded.scan(/.{4}/).join("-"), Base32.group(encoded)
    end

    test "rejects non-byte input and malformed encodings" do
      assert_raises(Base32::InvalidEncoding) { Base32.encode(nil) }

      [ nil, "", "lowercase", "AA=", "\xFF".b ].each do |encoded|
        assert_raises(Base32::InvalidEncoding) { Base32.decode(encoded) }
      end
    end

    test "rejects nonzero padding and zero-padded noncanonical lengths" do
      assert_raises(Base32::InvalidEncoding) { Base32.decode("B") }
      assert_raises(Base32::InvalidEncoding) { Base32.decode("A") }
    end
  end
end
