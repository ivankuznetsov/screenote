# frozen_string_literal: true

module InstanceAccounts
  class RevokeCredentials
    class << self
      def call(actor:, target:, channel: "web", clock: -> { Time.current })
        new(actor: actor, target: target, channel: channel, clock: clock).call
      end
    end

    def initialize(actor:, target:, channel: "web", clock: -> { Time.current })
      @actor = actor
      @target = target
      @channel = channel
      @clock = clock
    end

    def call
      DatabaseRetry.call do
        Installation.transaction do
          locked = InstanceAdministration::Authority.lock(actor: actor, target: target)
          next result(:unavailable) unless InstanceAdministration::Authority.available?(locked)
          next denied(locked, :forbidden) unless InstanceAdministration::Authority.authorized?(locked)
          next denied(locked, :not_found, reason: :target_not_found) unless locked.target

          credentials = CredentialRevoker.lock!(target: locked.target)
          revoked = CredentialRevoker.revoke!(credentials, at: current_time)
          InstanceAdministration::Audit.write!(
            installation: locked.installation,
            actor: locked.actor,
            target: locked.target,
            event_type: "credentials_revoked",
            channel: channel,
            metadata: revoked.as_json
          )
          result(:revoked, user: locked.target, details: revoked.as_json)
        end
      end
    rescue DatabaseRetry::Exhausted
      result(:retryable_busy)
    rescue ActiveRecord::RecordInvalid => error
      result(:invalid, errors: error.record.errors.to_hash)
    rescue ActiveRecord::ActiveRecordError
      result(:unavailable)
    end

    private

    attr_reader :actor, :target, :channel, :clock

    def denied(locked, status, reason: status)
      InstanceAdministration::Audit.denied!(
        installation: locked.installation,
        actor: locked.actor,
        target: locked.target,
        action: :revoke_credentials,
        reason: reason,
        channel: channel
      )
      result(status)
    end

    def current_time
      clock.call.to_time
    end

    def result(status, user: nil, errors: {}, details: {})
      InstanceAdministration::Result.new(status: status, user: user, errors: errors, details: details)
    end
  end
end
