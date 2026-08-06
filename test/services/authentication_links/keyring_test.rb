# frozen_string_literal: true

require "test_helper"

module AuthenticationLinks
  class KeyringTest < ActiveSupport::TestCase
    PRIMARY_SECRET = "primary-secret-key-base-0123456789abcdef"

    test "derives a stable domain-separated primary key and public fingerprint" do
      keyring = Keyring.new(secret_key_base: PRIMARY_SECRET)

      assert_equal "v1.7Lw-EjJ2A0iXidFTJd-nsJVl-KuD1lBQlD-4tIHeSi8", keyring.primary_key_id
      assert_equal "e0139759cecf2f3e5ebf04851495851734f946add1b407e2d87a2f4c6ccc549d",
        keyring.sign("payload", key_id: keyring.primary_key_id).unpack1("H*")
      assert_not_equal OpenSSL::HMAC.digest("SHA256", PRIMARY_SECRET, "payload"),
        keyring.sign("payload", key_id: keyring.primary_key_id)
    end

    test "accepts an explicitly identified prior file-backed key" do
      prior_key = Digest::SHA256.digest("prior authentication-link key")
      prior_key_id = Keyring.fingerprint(prior_key)
      keyring = Keyring.new(
        secret_key_base: PRIMARY_SECRET,
        prior_keys: { prior_key_id => prior_key }
      )

      assert_equal OpenSSL::HMAC.digest("SHA256", prior_key, "payload"),
        keyring.sign("payload", key_id: prior_key_id)
      assert_equal [ keyring.primary_key_id, prior_key_id ].sort, keyring.key_ids.sort
    end

    test "fails closed when a persisted key id is missing" do
      error = assert_raises(Keyring::MissingKey) do
        Keyring.new(secret_key_base: PRIMARY_SECRET).sign("payload", key_id: "v1.missing")
      end

      assert_equal "authentication-link derivation key is unavailable: v1.missing", error.message
    end

    test "reports configured keys and rejects non-string signing input" do
      keyring = Keyring.new(secret_key_base: PRIMARY_SECRET)

      assert keyring.include?(keyring.primary_key_id)
      assert_not keyring.include?("v1.missing")
      assert_raises(ArgumentError) { keyring.sign(nil) }
    end

    test "rejects a prior key whose configured id is not its fingerprint" do
      error = assert_raises(Keyring::KeyIdMismatch) do
        Keyring.new(
          secret_key_base: PRIMARY_SECRET,
          prior_keys: { "v1.wrong" => Digest::SHA256.digest("prior authentication-link key") }
        )
      end

      assert_equal "authentication-link derivation key id does not match its fingerprint", error.message
    end

    test "rejects weak primary material and malformed prior key bytes" do
      assert_raises(Keyring::InvalidKey) { Keyring.new(secret_key_base: "short") }

      assert_raises(Keyring::InvalidKey) do
        Keyring.new(secret_key_base: PRIMARY_SECRET, prior_keys: { "v1.any" => "short" })
      end

      assert_raises(Keyring::InvalidKey) do
        Keyring.new(secret_key_base: PRIMARY_SECRET, prior_keys: [])
      end
    end

    test "rejects a prior key that duplicates the derived primary fingerprint" do
      primary_key = OpenSSL::HMAC.digest("SHA256", PRIMARY_SECRET, Keyring::KEY_DERIVATION_CONTEXT)
      primary_key_id = Keyring.fingerprint(primary_key)

      error = assert_raises(Keyring::InvalidKey) do
        Keyring.new(secret_key_base: PRIMARY_SECRET, prior_keys: { primary_key_id => primary_key })
      end

      assert_equal "authentication-link derivation keys must have unique fingerprints", error.message
    end

    test "does not disclose key material through common serialization hooks" do
      keyring = Keyring.new(secret_key_base: PRIMARY_SECRET)

      [ keyring.inspect, keyring.to_s, keyring.as_json.to_s ].each do |rendered|
        assert_includes rendered, "FILTERED"
        assert_not_includes rendered, PRIMARY_SECRET
      end
    end
  end
end
