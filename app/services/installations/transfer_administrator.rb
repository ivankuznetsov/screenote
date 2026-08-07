# frozen_string_literal: true

module Installations
  class TransferAdministrator
    class << self
      def call(actor:, target:, operator: false, channel: "web", clock: -> { Time.current })
        new(
          actor: actor,
          target: target,
          operator: operator,
          channel: channel,
          clock: clock
        ).call
      end
    end

    def initialize(actor:, target:, operator: false, channel: "web", clock: -> { Time.current })
      @actor = actor
      @target = target
      @operator = operator
      @channel = channel
      @clock = clock
    end

    def call
      DatabaseRetry.call do
        Installation.transaction do
          locked = InstanceAdministration::Authority.lock(actor: actor, target: target)
          next result(:unavailable) unless InstanceAdministration::Authority.available?(locked)
          unless InstanceAdministration::Authority.authorized?(locked, operator: operator)
            next denied(locked, stale_actor_status(locked))
          end
          next denied(locked, :not_found, reason: :target_not_found) unless locked.target
          next result(:already_administrator, user: locked.target) if locked.target.id == locked.administrator.id
          next denied(locked, :target_inactive) unless locked.target.active?

          now = current_time
          tokens = AuthenticationToken.account_recovery
            .outstanding
            .where(issued_by_user_id: locked.administrator.id)
            .order(:id)
            .lock
            .to_a
          tokens.each { |token| token.transition_to!(:cancelled, at: now) }

          previous_administrator = locked.administrator
          locked.installation.update!(administrator: locked.target)
          InstanceAdministration::Audit.write!(
            installation: locked.installation,
            actor: operator ? nil : locked.actor,
            target: locked.target,
            event_type: "administrator_transferred",
            channel: channel,
            metadata: {
              "previous_administrator_id" => previous_administrator.id,
              "cancelled_recovery_tokens" => tokens.size
            }
          )
          result(:transferred, user: locked.target)
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
      "#<#{self.class.name} actor_id=#{actor&.id.inspect} target_id=#{target&.id.inspect}>"
    end

    alias_method :to_s, :inspect

    def as_json(*)
      { "operation" => self.class.name, "actor_id" => actor&.id, "target_id" => target&.id }
    end

    private

    attr_reader :actor, :target, :operator, :channel, :clock

    def stale_actor_status(locked)
      locked.actor&.active? ? :stale_administrator : :forbidden
    end

    def denied(locked, status, reason: status)
      InstanceAdministration::Audit.denied!(
        installation: locked.installation,
        actor: locked.actor,
        target: locked.target,
        action: :transfer_administrator,
        reason: reason,
        channel: channel
      ) unless operator
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
