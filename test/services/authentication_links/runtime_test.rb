# frozen_string_literal: true

require "test_helper"

module AuthenticationLinks
  class RuntimeTest < ActiveSupport::TestCase
    PRIMARY_SECRET = "primary-secret-key-base-0123456789abcdef"

    test "builds the primary keyring from application secret material" do
      runtime_keyring = Runtime.build(secret_key_base: PRIMARY_SECRET)
      expected = Keyring.new(secret_key_base: PRIMARY_SECRET)

      assert_equal expected.primary_key_id, runtime_keyring.primary_key_id
      assert_equal [ expected.primary_key_id ], runtime_keyring.key_ids
    end

    test "caches one immutable runtime keyring until explicitly reset" do
      Runtime.reset!
      Runtime.reset!
      first = Runtime.keyring

      assert_same first, Runtime.keyring

      Runtime.reset!
      assert_not_same first, Runtime.keyring
    ensure
      Runtime.reset!
    end

    test "strictly decodes fingerprint-bound prior keys" do
      prior_key = Digest::SHA256.digest("retained authentication-link key")
      key_id = Keyring.fingerprint(prior_key)
      encoded = Base64.urlsafe_encode64(prior_key, padding: false)

      keyring = Runtime.build(
        secret_key_base: PRIMARY_SECRET,
        encoded_prior_keys: JSON.generate(key_id => encoded)
      )

      assert_includes keyring.key_ids, key_id
      assert_equal OpenSSL::HMAC.digest("SHA256", prior_key, "message"),
        keyring.sign("message", key_id: key_id)
    end

    test "rejects malformed duplicate mismatched and excessive prior-key input without disclosure" do
      prior_key = Digest::SHA256.digest("retained authentication-link key")
      key_id = Keyring.fingerprint(prior_key)
      encoded = Base64.urlsafe_encode64(prior_key, padding: false)
      invalid_values = [
        "not-json",
        "[]",
        %({"#{key_id}":"#{encoded}","#{key_id}":"#{encoded}"}),
        JSON.generate("v1.#{'A' * 43}" => encoded),
        JSON.generate(key_id => "A" * 42),
        JSON.generate((Runtime::MAX_PRIOR_KEYS + 1).times.to_h { |index| [ "key-#{index}", encoded ] }),
        "{" + ("x" * Runtime::MAX_PRIOR_KEYS_BYTES) + "}"
      ]

      invalid_values.each do |value|
        error = assert_raises(Runtime::ConfigurationError) do
          Runtime.build(secret_key_base: PRIMARY_SECRET, encoded_prior_keys: value)
        end
        assert_equal "authentication-link key configuration is invalid", error.message
        assert_not_includes error.message, encoded
      end
    end
  end
end
