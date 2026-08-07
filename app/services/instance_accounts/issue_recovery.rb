# frozen_string_literal: true

module InstanceAccounts
  class IssueRecovery
    EXPIRY = 15.minutes
    TERMINAL_RETENTION = 24.hours

    class << self
      def call(
        actor:,
        target:,
        operator: false,
        channel: "web",
        clock: -> { Time.current },
        authentication_link_issuer: nil
      )
        new(
          actor: actor,
          target: target,
          operator: operator,
          channel: channel,
          clock: clock,
          authentication_link_issuer: authentication_link_issuer
        ).call
      end
    end

    def initialize(
      actor:,
      target:,
      operator: false,
      channel: "web",
      clock: -> { Time.current },
      authentication_link_issuer: nil
    )
      @actor = actor
      @target = target
      @operator = operator
      @channel = channel
      @clock = clock
      @authentication_link_issuer = authentication_link_issuer
    end

    def call
      DatabaseRetry.call do
        Installation.transaction do
          locked = InstanceAdministration::Authority.lock(actor: actor, target: target)
          next result(:unavailable) unless InstanceAdministration::Authority.available?(locked)
          unless InstanceAdministration::Authority.authorized?(locked, operator: operator)
            next denied(locked, :forbidden)
          end
          next denied(locked, :not_found, reason: :target_not_found) unless locked.target
          if operator && locked.target.id != locked.administrator.id
            next result(:stale_administrator)
          end
          next denied(locked, :inactive_target) unless locked.target.active?

          now = current_time
          purge_expired_terminal_tokens!(locked.target, now: now)
          issued = link_issuer(now: now).call(
            purpose: :account_recovery,
            subject: locked.target,
            expires_at: now + EXPIRY,
            issued_by_user: locked.administrator
          )
          InstanceAdministration::Audit.write!(
            installation: locked.installation,
            actor: operator ? nil : locked.actor,
            target: locked.target,
            event_type: "account_recovery_issued",
            channel: channel,
            metadata: { "authentication_token_id" => issued.token.id }
          )
          result(
            :issued,
            user: locked.target,
            token: issued.token,
            presentation: issued.presentation,
            expires_at: issued.token.expires_at
          )
        end
      end
    rescue DatabaseRetry::Exhausted
      result(:retryable_busy)
    rescue AuthenticationLinks::Issuer::Error, ActiveRecord::ActiveRecordError
      result(:unavailable)
    end

    def inspect
      "#<#{self.class.name} actor_id=#{actor&.id.inspect} target_id=#{target&.id.inspect} [FILTERED]>"
    end

    alias_method :to_s, :inspect

    def as_json(*)
      { "operation" => self.class.name, "actor_id" => actor&.id, "target_id" => target&.id }
    end

    private

    attr_reader :actor, :target, :operator, :channel, :clock, :authentication_link_issuer

    def link_issuer(now:)
      authentication_link_issuer || AuthenticationLinks::Issuer.new(
        origin: AuthenticationLinks::Runtime.origin,
        keyring: AuthenticationLinks::Runtime.keyring,
        clock: -> { now }
      )
    end

    def purge_expired_terminal_tokens!(subject, now:)
      AuthenticationToken.account_recovery
        .where(user_id: subject.id)
        .where.not(state: :outstanding)
        .where("terminal_at < ?", now - TERMINAL_RETENTION)
        .delete_all
    end

    def denied(locked, status, reason: status)
      InstanceAdministration::Audit.denied!(
        installation: locked.installation,
        actor: locked.actor,
        target: locked.target,
        action: :issue_recovery,
        reason: reason,
        channel: channel
      ) unless operator
      result(status)
    end

    def current_time
      clock.call.to_time
    end

    def result(status, user: nil, token: nil, presentation: nil, expires_at: nil, errors: {})
      InstanceAdministration::Result.new(
        status: status,
        user: user,
        token: token,
        presentation: presentation,
        expires_at: expires_at,
        errors: errors
      )
    end
  end
end
