# frozen_string_literal: true

require "test_helper"

module AuthenticationLinks
  class ResolverTest < ActiveSupport::TestCase
    PRIMARY_SECRET = "resolver-test-secret-key-base-0123456789abcdef"
    ORIGIN = "https://screenote.example"
    NOW = Time.utc(2026, 8, 5, 12)

    setup do
      @keyring = Keyring.new(secret_key_base: PRIMARY_SECRET)
      @issuer = Issuer.new(origin: ORIGIN, keyring: @keyring, clock: -> { NOW })
      @resolver = Resolver.new(keyring: @keyring, clock: -> { NOW })
      @user = users(:alice)
    end

    test "rejects unsupported result statuses" do
      assert_raises(ArgumentError) { Resolver::Result.new(status: :unavailable) }
    end

    test "resolves canonical fragment manual decoded and raw credentials without consuming them" do
      issued = issue(purpose: :password_reset)
      decoded = Presentation.decode(issued.presentation.fragment)
      credentials = [
        issued.presentation.fragment,
        "##{issued.presentation.fragment}",
        issued.presentation.manual_code,
        decoded,
        decoded.secret_bytes
      ]
      before = issued.token.attributes

      credentials.each do |credential|
        result = @resolver.resolve(credential: credential, expected_purpose: :password_reset)

        assert_equal :valid, result.status
        assert_equal issued.token, result.token
        assert result.valid?
      end

      assert_equal before, issued.token.reload.attributes
    end

    test "returns invalid for malformed credentials missing rows and wrong purposes" do
      issued = issue(purpose: :password_reset)

      malformed = @resolver.resolve(credential: "not-a-credential", expected_purpose: :password_reset)
      unknown = @resolver.resolve(
        credential: Presentation.new(origin: ORIGIN, purpose: :password_reset, secret_bytes: SecureRandom.random_bytes(32)).fragment,
        expected_purpose: :password_reset
      )
      wrong_purpose = @resolver.resolve(
        credential: issued.presentation.fragment,
        expected_purpose: :magic_link
      )
      malformed_decoded = @resolver.resolve(
        credential: Presentation::Decoded.new("short"),
        expected_purpose: :password_reset
      )
      unsupported_purpose = @resolver.resolve(
        credential: issued.presentation.fragment,
        expected_purpose: :unsupported
      )
      unsupported_type = @resolver.resolve(credential: Object.new, expected_purpose: :password_reset)

      [ malformed, unknown, wrong_purpose, malformed_decoded, unsupported_purpose, unsupported_type ].each do |result|
        assert_equal :invalid, result.status
        assert_nil result.token
        assert_nil result.as_json.fetch("token_id")
        assert_match "token_id=nil", result.inspect
      end
    end

    test "fails closed when the injected clock is invalid" do
      issued = issue(purpose: :password_reset)
      resolver = Resolver.new(keyring: @keyring, clock: -> { "not a time" })

      result = resolver.resolve(
        credential: issued.presentation.fragment,
        expected_purpose: :password_reset
      )

      assert_equal :invalid, result.status
      assert_nil result.token

      object_clock = Resolver.new(keyring: @keyring, clock: -> { Object.new })
      object_result = object_clock.resolve(
        credential: issued.presentation.fragment,
        expected_purpose: :password_reset
      )
      assert_equal :invalid, object_result.status
    end

    test "fails closed for a removed derivation key or tampered persisted metadata" do
      issued = issue(purpose: :password_reset)
      resolver_without_key = Resolver.new(
        keyring: Keyring.new(secret_key_base: "replacement-secret-key-base-0123456789abcdef"),
        clock: -> { NOW }
      )

      missing_key = resolver_without_key.resolve(
        credential: issued.presentation.fragment,
        expected_purpose: :password_reset
      )
      assert_equal :invalid, missing_key.status
      assert_nil missing_key.token

      AuthenticationToken.where(id: issued.token.id).update_all(generation: 99)
      tampered = @resolver.resolve(
        credential: issued.presentation.fragment,
        expected_purpose: :password_reset
      )
      assert_equal :invalid, tampered.status
      assert_nil tampered.token

      invalid_record = AuthenticationToken.new(id: issued.token.id, purpose: :password_reset, user: @user)
      invalid_model = with_authentication_token_find_by(invalid_record) do
        @resolver.revalidate(token_id: issued.token.id, expected_purpose: :password_reset)
      end
      assert_equal :invalid, invalid_model.status
      assert_nil invalid_model.token
    end

    test "maps verified lifecycle state to stable statuses" do
      consumed = issue(purpose: :password_reset)
      superseded = issue(purpose: :magic_link)
      cancelled = issue(purpose: :email_confirmation)
      expired = issue(purpose: :account_recovery, expires_at: NOW + 1.minute)

      consumed.token.transition_to!(:consumed, at: NOW + 1.second)
      superseded.token.transition_to!(:superseded, at: NOW + 1.second)
      cancelled.token.transition_to!(:cancelled, at: NOW + 1.second)

      assert_status :already_used, consumed
      assert_status :superseded, superseded
      assert_status :cancelled, cancelled

      later_resolver = Resolver.new(keyring: @keyring, clock: -> { NOW + 2.minutes })
      result = later_resolver.resolve(
        credential: expired.presentation.fragment,
        expected_purpose: :account_recovery
      )
      assert_equal :expired, result.status
      assert_equal expired.token, result.token
    end

    test "revalidates a tokenless session by token id purpose state digest and retained key" do
      issued = issue(purpose: :magic_link)

      result = @resolver.revalidate(token_id: issued.token.id, expected_purpose: :magic_link)
      assert_equal :valid, result.status
      assert_equal issued.token, result.token

      wrong_purpose = @resolver.revalidate(token_id: issued.token.id, expected_purpose: :password_reset)
      missing = @resolver.revalidate(token_id: -1, expected_purpose: :magic_link)
      removed_key = Resolver.new(
        keyring: Keyring.new(secret_key_base: "replacement-secret-key-base-0123456789abcdef"),
        clock: -> { NOW }
      ).revalidate(token_id: issued.token.id, expected_purpose: :magic_link)

      [ wrong_purpose, missing, removed_key ].each do |invalid|
        assert_equal :invalid, invalid.status
        assert_nil invalid.token
      end
    end

    test "results and invalid-input exceptions never serialize bearer material" do
      issued = issue(purpose: :password_reset)
      result = @resolver.resolve(
        credential: issued.presentation.fragment,
        expected_purpose: :password_reset
      )

      [ result.inspect, result.to_s, result.as_json.to_s ].each do |rendered|
        assert_not_includes rendered, issued.presentation.fragment
        assert_not_includes rendered, issued.presentation.manual_code
      end

      error = assert_raises(Presentation::InvalidEncoding) do
        Presentation.decode("#{issued.presentation.fragment}secret-suffix")
      end
      assert_not_includes error.message, issued.presentation.fragment
    end

    private

    def with_authentication_token_find_by(result)
      singleton = AuthenticationToken.singleton_class
      original = AuthenticationToken.method(:find_by)
      singleton.define_method(:find_by) { |**| result }
      yield
    ensure
      singleton&.define_method(:find_by, original)
    end

    def issue(purpose:, expires_at: NOW + 15.minutes)
      result = nil
      AuthenticationToken.transaction do
        locked_user = User.lock.find(@user.id)
        result = @issuer.call(
          purpose: purpose,
          subject: locked_user,
          expires_at: expires_at,
          issued_by_user: (locked_user if purpose.to_sym == :account_recovery)
        )
      end
      result
    end

    def assert_status(expected, issued)
      result = @resolver.resolve(
        credential: issued.presentation.fragment,
        expected_purpose: issued.token.purpose
      )
      assert_equal expected, result.status
      assert_equal issued.token, result.token
    end
  end
end
