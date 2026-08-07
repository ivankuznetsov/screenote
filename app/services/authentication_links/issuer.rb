# frozen_string_literal: true

require "openssl"
require "securerandom"

module AuthenticationLinks
  class Issuer
    MAX_COLLISION_ATTEMPTS = 3

    class Error < StandardError; end
    class OutsideTransaction < Error; end
    class InvalidPurpose < Error; end
    class InvalidSubject < Error; end
    class InvalidIssuer < Error; end
    class InvalidExpiry < Error; end
    class InvalidToken < Error; end
    class CorruptState < Error; end
    class Collision < Error; end

    class Result
      attr_reader :token, :presentation

      def initialize(token:, presentation:)
        @token = token
        @presentation = presentation
        freeze
      end

      def inspect
        "#<#{self.class.name} [FILTERED]>"
      end

      alias_method :to_s, :inspect

      def as_json(*)
        "[FILTERED]"
      end
    end

    def initialize(
      origin:,
      keyring:,
      clock: -> { Time.current },
      connection: nil,
      random_hex: -> { SecureRandom.hex(32) },
      token_creator: ->(attributes) { AuthenticationToken.create!(attributes) }
    )
      @origin = origin
      @deriver = Deriver.new(keyring: keyring)
      @clock = clock
      @connection = connection
      @random_hex = random_hex
      @token_creator = token_creator
    end

    # This is intentionally an inner service. The caller owns the outer
    # transaction, retries, and the global-order lock on the exact subject.
    def call(purpose:, subject:, expires_at:, issued_by_user: nil)
      ensure_transaction!

      purpose = canonical_purpose(purpose)
      validate_subject!(purpose, subject)
      issued_by_user = canonical_issuer(purpose, issued_by_user)
      now = current_time
      expires_at = canonical_expiry(expires_at, now: now)
      tokens = token_scope(purpose, subject).order(:id).lock.to_a
      outstanding = tokens.find(&:outstanding?)

      generation = tokens.filter_map(&:generation).max.to_i + 1
      derivation_id, derived = available_derivation(
        purpose: purpose,
        subject: subject,
        generation: generation,
        expires_at: expires_at
      )
      presentation = Presentation.new(
        origin: @origin,
        purpose: purpose,
        secret_bytes: derived.secret_bytes
      )

      if outstanding && !outstanding.transition_to!(:superseded, at: now)
        raise CorruptState, "authentication-link token changed during issuance"
      end

      attributes = {
        purpose: purpose,
        subject: subject,
        generation: generation,
        derivation_id: derivation_id,
        derivation_key_id: derived.key_id,
        token_digest: derived.digest,
        expires_at: expires_at,
        state: :outstanding,
        created_at: now,
        updated_at: now
      }
      attributes[:issued_by_user] = issued_by_user if issued_by_user
      token = @token_creator.call(attributes)

      Result.new(token: token, presentation: presentation)
    end

    def re_present(token:)
      token = persisted_token(token)
      raise InvalidToken, "authentication-link token is unavailable" unless presentable?(token)

      derived = derive(token)
      unless secure_equal?(derived.key_id, token.derivation_key_id) &&
          secure_equal?(derived.digest, token.token_digest)
        raise InvalidToken, "authentication-link token is unavailable"
      end

      Presentation.new(
        origin: @origin,
        purpose: token.purpose,
        secret_bytes: derived.secret_bytes
      )
    end

    private

    def ensure_transaction!
      connection = @connection || AuthenticationToken.connection
      return if connection.transaction_open?

      raise OutsideTransaction, "authentication-link issuance requires an open outer transaction"
    end

    def canonical_purpose(value)
      value = value.to_s if value.is_a?(Symbol)
      unless value.is_a?(String) && AuthenticationToken.purposes.key?(value)
        raise InvalidPurpose, "authentication-link purpose is invalid"
      end

      value
    end

    def validate_subject!(purpose, subject)
      expected_class = purpose == "invitation" ? ProjectInvitation : User
      valid = subject.is_a?(expected_class) && subject.persisted? && !subject.destroyed? &&
        subject.id.is_a?(Integer) && subject.id.positive? && !subject.has_changes_to_save?
      return if valid

      raise InvalidSubject, "authentication-link subject is invalid for its purpose"
    end

    def canonical_issuer(purpose, issued_by_user)
      if purpose == "account_recovery"
        valid = issued_by_user.is_a?(User) && issued_by_user.persisted? &&
          !issued_by_user.destroyed? && issued_by_user.id.is_a?(Integer) &&
          issued_by_user.id.positive? && !issued_by_user.has_changes_to_save?
        return issued_by_user if valid
      elsif issued_by_user.nil?
        return nil
      end

      raise InvalidIssuer, "authentication-link issuer is invalid for its purpose"
    end

    def canonical_expiry(value, now:)
      expires_at = value.to_time if value.respond_to?(:to_time)
      unless expires_at.is_a?(Time) && expires_at > now
        raise InvalidExpiry, "authentication-link expiry must be in the future"
      end

      expires_at
    end

    def current_time
      value = @clock.call
      value = value.to_time if value.respond_to?(:to_time)
      return value if value.is_a?(Time)

      raise InvalidExpiry, "authentication-link clock did not return a time"
    end

    def token_scope(purpose, subject)
      subject_column = subject.is_a?(ProjectInvitation) ? :project_invitation_id : :user_id
      AuthenticationToken.where(purpose: purpose, subject_column => subject.id)
    end

    def available_derivation(purpose:, subject:, generation:, expires_at:)
      MAX_COLLISION_ATTEMPTS.times do
        derivation_id = @random_hex.call
        derived = @deriver.derive(
          purpose: purpose,
          subject_type: subject.class.base_class.name,
          subject_id: subject.id,
          generation: generation,
          derivation_id: derivation_id,
          expires_at: expires_at
        )
        collision = AuthenticationToken.where(derivation_id: derivation_id)
          .or(AuthenticationToken.where(token_digest: derived.digest))
          .exists?
        return [ derivation_id, derived ] unless collision
      end

      raise Collision, "authentication-link credential collision could not be resolved"
    end

    def persisted_token(token)
      return unless token.is_a?(AuthenticationToken) && token.persisted?

      AuthenticationToken.find_by(id: token.id)
    end

    def presentable?(token)
      token&.valid? && token.outstanding? && token.expires_at > current_time
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

    def secure_equal?(actual, expected)
      actual.is_a?(String) && expected.is_a?(String) &&
        actual.bytesize == expected.bytesize &&
        OpenSSL.fixed_length_secure_compare(actual, expected)
    end
  end
end
