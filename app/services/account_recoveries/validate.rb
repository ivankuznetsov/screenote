# frozen_string_literal: true

module AccountRecoveries
  class Validate
    TERMINAL_STATUSES = %i[invalid expired already_used superseded cancelled].freeze

    class << self
      def call(token_id:, resolver: nil, clock: -> { Time.current })
        resolver ||= AuthenticationLinks::Resolver.new(
          keyring: AuthenticationLinks::Runtime.keyring,
          clock: clock
        )
        new(token_id: token_id, resolver: resolver).call
      end
    end

    def initialize(token_id:, resolver:)
      @token_id = token_id
      @resolver = resolver
    end

    def call
      return result(:invalid) unless token_id.is_a?(Integer) && token_id.positive?

      preflight = resolver.revalidate(token_id: token_id, expected_purpose: :account_recovery)
      return resolution_result(preflight) unless preflight.valid?

      DatabaseRetry.call do
        Installation.transaction do
          validate_locked(preflight.token)
        end
      end
    rescue DatabaseRetry::Exhausted
      result(:retryable_busy)
    rescue ActiveRecord::ActiveRecordError
      result(:unavailable)
    end

    private

    attr_reader :token_id, :resolver

    def validate_locked(token_hint)
      installation = Installation.lock.find_by(singleton_key: Installation::SINGLETON_KEY)
      return result(:unavailable) unless installation

      ids = [ installation.administrator_id, token_hint.user_id, token_hint.issued_by_user_id ].compact
      users = AuthorityLock.users!(User.where(id: ids).to_a).index_by(&:id)
      administrator = users[installation.administrator_id]
      target = users[token_hint.user_id]
      issuer = users[token_hint.issued_by_user_id]
      token = AuthenticationToken.lock.find_by(id: token_id)
      return result(:invalid) unless token

      resolution = resolver.revalidate(token_id: token.id, expected_purpose: :account_recovery)
      return resolution_result(resolution) unless resolution.valid?
      return result(:unavailable) unless installation.valid? && installation.self_hosted? && installation.claimed?
      return result(:issuer_revoked) unless administrator.active? && issuer&.id == administrator.id
      return result(:inactive_target) unless target&.active?
      return result(:invalid) unless token.user_id == target.id && token.issued_by_user_id == issuer.id

      result(:valid, user: target, token: token)
    end

    def resolution_result(resolution)
      status = TERMINAL_STATUSES.include?(resolution.status) ? resolution.status : :invalid
      result(status)
    end

    def result(status, user: nil, token: nil)
      InstanceAdministration::Result.new(status: status, user: user, token: token)
    end
  end
end
