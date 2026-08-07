# frozen_string_literal: true

module InstanceAccounts
  class Restore
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
          next result(:already_active, user: locked.target) if locked.target.active?

          locked.target.update!(access_status: :active)
          InstanceAdministration::Audit.write!(
            installation: locked.installation,
            actor: locked.actor,
            target: locked.target,
            event_type: "account_restored",
            channel: channel
          )
          result(:restored, user: locked.target)
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
        action: :restore,
        reason: reason,
        channel: channel
      )
      result(status)
    end

    def result(status, user: nil, errors: {})
      InstanceAdministration::Result.new(status: status, user: user, errors: errors)
    end
  end
end
