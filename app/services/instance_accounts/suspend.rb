# frozen_string_literal: true

module InstanceAccounts
  class Suspend
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
          if locked.target.id == locked.administrator.id
            next denied(locked, :cannot_suspend_administrator, reason: :current_administrator)
          end
          next result(:already_suspended, user: locked.target) if locked.target.suspended?

          now = current_time
          credentials = CredentialRevoker.lock!(target: locked.target)
          revoked = CredentialRevoker.revoke!(credentials, at: now)
          locked.target.update!(access_status: :suspended)
          InstanceAdministration::Audit.write!(
            installation: locked.installation,
            actor: locked.actor,
            target: locked.target,
            event_type: "account_suspended",
            channel: channel,
            metadata: revoked.as_json
          )
          result(:suspended, user: locked.target, details: revoked.as_json)
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
        action: :suspend,
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
