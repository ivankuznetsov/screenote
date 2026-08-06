# frozen_string_literal: true

module AccountRecoveries
  class Consume
    TERMINAL_STATUSES = %i[invalid expired already_used superseded cancelled].freeze

    class << self
      def call(
        token_id:,
        password:,
        password_confirmation:,
        resolver: nil,
        channel: "web",
        clock: -> { Time.current }
      )
        new(
          token_id: token_id,
          password: password,
          password_confirmation: password_confirmation,
          resolver: resolver,
          channel: channel,
          clock: clock
        ).call
      end
    end

    def initialize(
      token_id:,
      password:,
      password_confirmation:,
      resolver: nil,
      channel: "web",
      clock: -> { Time.current }
    )
      @token_id = token_id
      @password = password.to_s.dup.freeze
      @password_confirmation = password_confirmation.to_s.dup.freeze
      @clock = clock
      @channel = channel
      @resolver = resolver || AuthenticationLinks::Resolver.new(
        keyring: AuthenticationLinks::Runtime.keyring,
        clock: clock
      )
    end

    def call
      return result(:invalid) unless token_id.is_a?(Integer) && token_id.positive?

      preflight = resolver.revalidate(token_id: token_id, expected_purpose: :account_recovery)
      return resolution_result(preflight) unless preflight.valid?

      DatabaseRetry.call do
        Installation.transaction do
          consume_locked(preflight.token)
        end
      end
    rescue DatabaseRetry::Exhausted
      result(:retryable_busy)
    rescue ActiveRecord::RecordInvalid => error
      result(:invalid, errors: error.record.errors.to_hash)
    rescue ActiveRecord::ActiveRecordError
      result(:unavailable)
    end

    def inspect
      "#<#{self.class.name} token_id=#{token_id.inspect} [FILTERED]>"
    end

    alias_method :to_s, :inspect

    def as_json(*)
      { "operation" => self.class.name, "token_id" => token_id }
    end

    private

    attr_reader :token_id, :password, :password_confirmation, :resolver, :channel, :clock

    def consume_locked(token_hint)
      installation = Installation.lock.find_by(singleton_key: Installation::SINGLETON_KEY)
      return result(:unavailable) unless installation

      ids = [ installation.administrator_id, token_hint.user_id, token_hint.issued_by_user_id ].compact
      users = AuthorityLock.users!(User.where(id: ids).to_a).index_by(&:id)
      administrator = users[installation.administrator_id]
      target = users[token_hint.user_id]
      issuer = users[token_hint.issued_by_user_id]
      return result(:unavailable) unless installation.valid? && installation.self_hosted? && installation.claimed?
      return result(:issuer_revoked) unless administrator.active? && issuer&.id == administrator.id
      return result(:inactive_target) unless target&.active?

      target.assign_attributes(password: password, password_confirmation: password_confirmation)
      return result(:invalid, errors: target.errors.to_hash) unless target.valid?

      credential_locks = InstanceAccounts::CredentialRevoker.lock!(target: target)
      token = credential_locks.authentication_tokens.find { |candidate| candidate.id == token_id }
      return result(:invalid) unless token
      return result(:invalid) unless token.user_id == target.id && token.issued_by_user_id == issuer.id

      resolution = resolver.revalidate(token_id: token.id, expected_purpose: :account_recovery)
      return resolution_result(resolution) unless resolution.valid?

      now = current_time
      return result(:already_used) unless token.transition_to!(:consumed, at: now)

      revoked = InstanceAccounts::CredentialRevoker.revoke!(
        credential_locks,
        at: now,
        preserve_authentication_token_id: token.id
      )
      target.save!

      InstanceAdministration::Audit.write!(
        installation: installation,
        actor: target,
        target: target,
        event_type: "account_recovered",
        channel: channel,
        metadata: revoked.as_json.merge("authentication_token_id" => token.id)
      )
      result(:recovered, user: target)
    end

    def resolution_result(resolution)
      status = TERMINAL_STATUSES.include?(resolution.status) ? resolution.status : :invalid
      result(status)
    end

    def current_time
      clock.call.to_time
    end

    def result(status, user: nil, errors: {})
      InstanceAdministration::Result.new(status: status, user: user, errors: errors)
    end
  end
end
