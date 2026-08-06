# frozen_string_literal: true

require "test_helper"

module AuthenticationLinks
  class IssuerTest < ActiveSupport::TestCase
    PRIMARY_SECRET = "issuer-test-secret-key-base-0123456789abcdef"
    ORIGIN = "https://screenote.example"
    NOW = Time.utc(2026, 8, 5, 12)

    Connection = Data.define(:transaction_open?)

    setup do
      @keyring = Keyring.new(secret_key_base: PRIMARY_SECRET)
      @issuer = Issuer.new(origin: ORIGIN, keyring: @keyring, clock: -> { NOW })
      @user = users(:alice)
      @invitation = project_invitations(:pending_invitation)
    end

    test "issues a digest-only purpose-bound credential from a locked subject" do
      result = issue(purpose: :invitation, subject: @invitation)
      token = result.token
      decoded = Presentation.decode(result.presentation.fragment)

      assert_equal @invitation, token.subject
      assert_equal "invitation", token.purpose
      assert_equal 1, token.generation
      assert_equal @keyring.primary_key_id, token.derivation_key_id
      assert_equal decoded.digest, token.token_digest
      assert_equal ORIGIN, result.presentation.origin
      assert_equal "#{ORIGIN}/authentication-links/invitation##{result.presentation.fragment}",
        result.presentation.url
      assert_equal [], token.attribute_names.grep(/raw|plaintext|credential|secret/)
      assert_includes result.inspect, "FILTERED"
      assert_equal "[FILTERED]", result.as_json
    end

    test "supersedes the one outstanding token and increments generation monotonically" do
      first = issue(purpose: :password_reset, subject: @user).token
      second = issue(purpose: :password_reset, subject: @user).token

      assert first.reload.superseded?
      assert_equal NOW, first.terminal_at
      assert second.outstanding?
      assert_equal 2, second.generation

      second.transition_to!(:consumed, at: NOW + 1.second)
      third = issue(purpose: :password_reset, subject: @user).token

      assert_equal 3, third.generation
      assert third.outstanding?
    end

    test "validates the transaction purpose subject expiry and origin before mutation" do
      outside_transaction = Issuer.new(
        origin: ORIGIN,
        keyring: @keyring,
        clock: -> { NOW },
        connection: Connection.new(transaction_open?: false)
      )

      assert_raises(Issuer::OutsideTransaction) do
        outside_transaction.call(
          purpose: :password_reset,
          subject: @user,
          expires_at: NOW + 15.minutes
        )
      end

      assert_no_difference -> { AuthenticationToken.count } do
        AuthenticationToken.transaction do
          assert_raises(Issuer::InvalidSubject) do
            @issuer.call(purpose: :invitation, subject: @user, expires_at: NOW + 15.minutes)
          end
          assert_raises(Issuer::InvalidPurpose) do
            @issuer.call(purpose: :unknown, subject: @user, expires_at: NOW + 15.minutes)
          end
          assert_raises(Issuer::InvalidExpiry) do
            @issuer.call(purpose: :password_reset, subject: @user, expires_at: NOW)
          end
          assert_raises(Issuer::InvalidExpiry) do
            @issuer.call(purpose: :password_reset, subject: @user, expires_at: Object.new)
          end

          invalid_origin = Issuer.new(origin: "https://screenote.example/path", keyring: @keyring, clock: -> { NOW })
          assert_raises(Presentation::InvalidOrigin) do
            invalid_origin.call(
              purpose: :password_reset,
              subject: User.lock.find(@user.id),
              expires_at: NOW + 15.minutes
            )
          end
        end
      end
    end

    test "rejects a clock value that cannot be converted to a time" do
      issuer = Issuer.new(origin: ORIGIN, keyring: @keyring, clock: -> { Object.new })

      AuthenticationToken.transaction do
        locked_user = User.lock.find(@user.id)
        assert_raises(Issuer::InvalidExpiry) do
          issuer.call(
            purpose: "password_reset",
            subject: locked_user,
            expires_at: NOW + 15.minutes
          )
        end
      end
    end

    test "outer rollback restores a superseded token and removes the replacement" do
      original = issue(purpose: :magic_link, subject: @user).token

      AuthenticationToken.transaction do
        locked_user = User.lock.find(@user.id)
        @issuer.call(purpose: :magic_link, subject: locked_user, expires_at: NOW + 30.minutes)
        raise ActiveRecord::Rollback
      end

      assert original.reload.outstanding?
      assert_equal [ 1 ], AuthenticationToken.where(purpose: :magic_link, user: @user).pluck(:generation)
    end

    test "a derivation collision is exhausted before the outstanding token is terminalized" do
      original = issue(purpose: :email_confirmation, subject: @user).token
      collision = "f" * 64
      create_existing_collision!(collision)

      collision_issuer = Issuer.new(
        origin: ORIGIN,
        keyring: @keyring,
        clock: -> { NOW },
        random_hex: -> { collision }
      )
      assert_raises(Issuer::Collision) do
        AuthenticationToken.transaction do
          locked_user = User.lock.find(@user.id)
          collision_issuer.call(
            purpose: :email_confirmation,
            subject: locked_user,
            expires_at: NOW + 30.minutes
          )
        end
      end

      assert original.reload.outstanding?
      assert_equal [ 1 ], AuthenticationToken.where(purpose: :email_confirmation, user: @user).pluck(:generation)
    end

    test "a late uniqueness failure rolls the entire caller transaction back" do
      original = issue(purpose: :account_recovery, subject: @user).token
      failing_issuer = Issuer.new(
        origin: ORIGIN,
        keyring: @keyring,
        clock: -> { NOW },
        token_creator: ->(*) { raise ActiveRecord::RecordNotUnique }
      )

      assert_raises(ActiveRecord::RecordNotUnique) do
        AuthenticationToken.transaction do
          locked_user = User.lock.find(@user.id)
          failing_issuer.call(
            purpose: :account_recovery,
            subject: locked_user,
            expires_at: NOW + 30.minutes,
            issued_by_user: locked_user
          )
        end
      end

      assert original.reload.outstanding?
      assert_equal [ 1 ], AuthenticationToken.where(purpose: :account_recovery, user: @user).pluck(:generation)
    end

    test "detects an outstanding token changed concurrently before superseding it" do
      original = issue(purpose: :magic_link, subject: @user).token
      racing_issuer = Issuer.new(
        origin: ORIGIN,
        keyring: @keyring,
        clock: -> { NOW + 1.minute },
        random_hex: lambda do
          AuthenticationToken.where(id: original.id).update_all(
            state: AuthenticationToken.states.fetch(:cancelled),
            terminal_at: NOW + 1.minute,
            updated_at: NOW + 1.minute
          )
          SecureRandom.hex(32)
        end
      )

      assert_raises(Issuer::CorruptState) do
        AuthenticationToken.transaction do
          locked_user = User.lock.find(@user.id)
          racing_issuer.call(
            purpose: "magic_link",
            subject: locked_user,
            expires_at: NOW + 30.minutes
          )
        end
      end

      assert original.reload.outstanding?
    end

    test "requires immutable user issuer provenance only for account recovery" do
      AuthenticationToken.transaction do
        locked_user = User.lock.find(@user.id)

        assert_raises(Issuer::InvalidIssuer) do
          @issuer.call(
            purpose: :account_recovery,
            subject: locked_user,
            expires_at: NOW + 15.minutes
          )
        end
        assert_raises(Issuer::InvalidIssuer) do
          @issuer.call(
            purpose: :password_reset,
            subject: locked_user,
            expires_at: NOW + 15.minutes,
            issued_by_user: locked_user
          )
        end
      end

      issued = issue(purpose: :account_recovery, subject: @user)
      assert_equal @user, issued.token.issued_by_user
    end

    test "re-presents an active token only after rederiving and verifying persisted metadata" do
      issued = issue(purpose: :password_reset, subject: @user)
      represented = @issuer.re_present(token: issued.token)

      assert_equal issued.presentation.fragment, represented.fragment
      assert_equal issued.presentation.manual_code, represented.manual_code

      AuthenticationToken.where(id: issued.token.id).update_all(generation: 99)
      assert_raises(Issuer::InvalidToken) { @issuer.re_present(token: issued.token) }
    end

    test "re-presentation fails closed after key removal or terminalization" do
      issued = issue(purpose: :password_reset, subject: @user)
      replacement_issuer = Issuer.new(
        origin: ORIGIN,
        keyring: Keyring.new(secret_key_base: "replacement-secret-key-base-0123456789abcdef"),
        clock: -> { NOW }
      )

      assert_raises(Keyring::MissingKey) { replacement_issuer.re_present(token: issued.token) }

      issued.token.transition_to!(:cancelled, at: NOW + 1.second)
      assert_raises(Issuer::InvalidToken) { @issuer.re_present(token: issued.token) }

      assert_raises(Issuer::InvalidToken) { @issuer.re_present(token: nil) }
      assert_raises(Issuer::InvalidToken) do
        @issuer.re_present(token: AuthenticationToken.new)
      end
    end

    private

    def issue(purpose:, subject:, expires_at: NOW + 15.minutes)
      result = nil
      AuthenticationToken.transaction do
        locked_subject = subject.class.lock.find(subject.id)
        result = @issuer.call(
          purpose: purpose,
          subject: locked_subject,
          expires_at: expires_at,
          issued_by_user: (locked_subject if purpose.to_sym == :account_recovery)
        )
      end
      result
    end

    def create_existing_collision!(derivation_id)
      user = users(:bob)
      AuthenticationToken.create!(
        purpose: :magic_link,
        subject: user,
        generation: 1,
        derivation_id: derivation_id,
        derivation_key_id: @keyring.primary_key_id,
        token_digest: "e" * 64,
        expires_at: NOW + 1.hour,
        state: :outstanding,
        created_at: NOW,
        updated_at: NOW
      )
    end
  end
end
