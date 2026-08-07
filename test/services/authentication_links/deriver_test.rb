# frozen_string_literal: true

require "test_helper"

module AuthenticationLinks
  class DeriverTest < ActiveSupport::TestCase
    PRIMARY_SECRET = "primary-secret-key-base-0123456789abcdef"
    METADATA = {
      purpose: "invitation",
      subject_type: "ProjectInvitation",
      subject_id: 42,
      generation: 3,
      derivation_id: "00112233445566778899aabbccddeeff00112233445566778899aabbccddeeff",
      expires_at: Time.utc(2030, 1, 1)
    }.freeze

    setup do
      @keyring = Keyring.new(secret_key_base: PRIMARY_SECRET)
      @deriver = Deriver.new(keyring: @keyring)
    end

    test "requires the versioned authentication-link keyring" do
      error = assert_raises(ArgumentError) { Deriver.new(keyring: Object.new) }

      assert_equal "keyring must be an AuthenticationLinks::Keyring", error.message
    end

    test "derives the stable versioned canonical tuple vector" do
      result = @deriver.derive(**METADATA)

      assert_equal @keyring.primary_key_id, result.key_id
      assert_equal 32, result.secret_bytes.bytesize
      assert_equal "lsY9jAoyVh619LkSbaBLErWLHlSpay7RfLtaZsd-pnM",
        Base64.urlsafe_encode64(result.secret_bytes, padding: false)
      assert_equal "0d0386383aec4abaf86ea177344054107dc2d3417d99fd3a6770f5bbd95f2d9c", result.digest
      assert_equal result.digest, result.token_digest
      assert @deriver.matches_digest?(expected_digest: result.digest, **METADATA)

      epoch_result = @deriver.derive(**METADATA.merge(expires_at: METADATA.fetch(:expires_at).to_i))
      assert_equal result.secret_bytes, epoch_result.secret_bytes
    end

    test "canonicalizes a symbol purpose to the persisted string value" do
      string_result = @deriver.derive(**METADATA)
      symbol_result = @deriver.derive(**METADATA.merge(purpose: :invitation))

      assert_equal string_result.secret_bytes, symbol_result.secret_bytes
      assert_equal string_result.digest, symbol_result.digest
    end

    test "every metadata field is bound into the derived credential" do
      baseline = @deriver.derive(**METADATA).secret_bytes
      alternatives = [
        METADATA.merge(purpose: "password_reset"),
        METADATA.merge(subject_type: "User"),
        METADATA.merge(subject_id: 43),
        METADATA.merge(generation: 4),
        METADATA.merge(derivation_id: "10112233445566778899aabbccddeeff00112233445566778899aabbccddeeff"),
        METADATA.merge(expires_at: Time.utc(2030, 1, 1, 0, 0, 1))
      ]

      alternatives.each do |metadata|
        assert_not_equal baseline, @deriver.derive(**metadata).secret_bytes
      end
    end

    test "selects a retained key by persisted key id" do
      prior_key = Digest::SHA256.digest("prior authentication-link key")
      prior_key_id = Keyring.fingerprint(prior_key)
      deriver = Deriver.new(
        keyring: Keyring.new(
          secret_key_base: PRIMARY_SECRET,
          prior_keys: { prior_key_id => prior_key }
        )
      )

      current = deriver.derive(**METADATA)
      prior = deriver.derive(**METADATA, key_id: prior_key_id)

      assert_not_equal current.secret_bytes, prior.secret_bytes
      assert_equal prior_key_id, prior.key_id
      assert deriver.matches_digest?(expected_digest: prior.digest, **METADATA, key_id: prior_key_id)
      assert_not deriver.matches_digest?(expected_digest: current.digest, **METADATA, key_id: prior_key_id)
    end

    test "fails closed when a retained key has been removed" do
      assert_raises(Keyring::MissingKey) do
        @deriver.derive(**METADATA, key_id: "v1.removed")
      end
    end

    test "rejects noncanonical metadata and persisted digests" do
      invalid_metadata = [
        METADATA.merge(purpose: "Invitation"),
        METADATA.merge(subject_type: "project invitation"),
        METADATA.merge(subject_id: "42"),
        METADATA.merge(generation: 0),
        METADATA.merge(derivation_id: "short"),
        METADATA.merge(expires_at: "2030-01-01")
      ]

      invalid_metadata.each do |metadata|
        assert_raises(Deriver::InvalidMetadata) { @deriver.derive(**metadata) }
      end

      assert_raises(Deriver::InvalidDigest) do
        @deriver.matches_digest?(expected_digest: "A" * 64, **METADATA)
      end
      assert_raises(Deriver::InvalidDigest) do
        @deriver.matches_digest?(expected_digest: ("\xFF" * 64).b, **METADATA)
      end
    end

    test "does not disclose the derived credential through common serialization hooks" do
      result = @deriver.derive(**METADATA)
      encoded_secret = Base64.urlsafe_encode64(result.secret_bytes, padding: false)

      [ result.inspect, result.to_s, result.as_json.to_s ].each do |rendered|
        assert_includes rendered, "FILTERED"
        assert_not_includes rendered, encoded_secret
        assert_not_includes rendered, result.digest
      end


      [ @deriver.inspect, @deriver.to_s, @deriver.as_json.to_s ].each do |rendered|
        assert_includes rendered, "FILTERED"
        assert_not_includes rendered, encoded_secret
        assert_not_includes rendered, result.digest
      end
    end
  end
end
