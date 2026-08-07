# frozen_string_literal: true

require "test_helper"

module AuthenticationLinks
  class KeyringPreflightTest < ActiveSupport::TestCase
    MissingTableConnection = Class.new do
      def data_source_exists?(_table_name)
        false
      end
    end

    setup do
      @primary = Keyring.new(secret_key_base: "primary-secret-key-base-0123456789abcdef")
      @user = users(:alice)
    end

    test "accepts active tokens backed by the configured keyring" do
      create_token!(key_id: @primary.primary_key_id)

      assert KeyringPreflight.call(keyring: @primary)
    end

    test "permits startup before the authentication token table exists" do
      connection = MissingTableConnection.new

      assert KeyringPreflight.call(keyring: @primary, connection: connection)
    end

    test "fails closed when an active token references a removed key" do
      prior_key = Digest::SHA256.digest("removed authentication-link key")
      create_token!(key_id: Keyring.fingerprint(prior_key))

      error = assert_raises(KeyringPreflight::MissingKey) do
        KeyringPreflight.call(keyring: @primary)
      end
      assert_equal "an active authentication link requires an unavailable prior derivation key", error.message
    end

    test "does not require retained keys for expired or terminal tokens" do
      prior_key = Digest::SHA256.digest("retired authentication-link key")
      key_id = Keyring.fingerprint(prior_key)
      create_token!(key_id: key_id, expires_at: 1.minute.ago)
      terminal = create_token!(key_id: key_id, purpose: :magic_link)
      terminal.update_columns(
        state: AuthenticationToken.states.fetch(:cancelled),
        terminal_at: Time.current,
        updated_at: Time.current
      )

      assert KeyringPreflight.call(keyring: @primary)
    end

    private

    def create_token!(key_id:, purpose: :password_reset, expires_at: 15.minutes.from_now)
      now = 2.minutes.ago
      AuthenticationToken.create!(
        purpose: purpose,
        subject: @user,
        generation: AuthenticationToken.where(user: @user, purpose: purpose).maximum(:generation).to_i + 1,
        derivation_id: SecureRandom.hex(32),
        derivation_key_id: key_id,
        token_digest: SecureRandom.hex(32),
        expires_at: expires_at,
        created_at: now,
        updated_at: now
      )
    end
  end
end
