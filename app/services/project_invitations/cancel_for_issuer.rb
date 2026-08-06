# frozen_string_literal: true

module ProjectInvitations
  class CancelForIssuer
    class OutsideTransaction < StandardError; end
    class InvalidScope < StandardError; end

    LockScope = Data.define(:issuer_id, :project_ids, :invitations)
    Result = Data.define(:status, :invitations)

    class << self
      def lock_scope!(issuer:, projects:)
        ensure_transaction!
        raise InvalidScope, "invitation issuer must be persisted" unless issuer&.persisted?

        projects = Array(projects)
        unless projects.all?(&:persisted?)
          raise InvalidScope, "invitation projects must be persisted and prelocked"
        end

        project_ids = projects.map(&:id).uniq.sort.freeze
        invitations = ProjectInvitation.pending
          .where(inviter_id: issuer.id, project_id: project_ids)
          .order(:id)
          .lock
          .to_a

        LockScope.new(
          issuer_id: issuer.id,
          project_ids: project_ids,
          invitations: invitations.freeze
        )
      end

      def call(issuer:, scope:, clock: -> { Time.current })
        ensure_transaction!
        validate_scope!(issuer, scope)

        invitations = scope.invitations.select do |invitation|
          invitation.persisted? && invitation.pending? &&
            invitation.inviter_id == issuer.id && scope.project_ids.include?(invitation.project_id)
        end
        return Result.new(status: :none, invitations: [].freeze) if invitations.empty?

        now = clock.call.to_time
        invitations.each do |invitation|
          invitation.update_columns(
            status: ProjectInvitation.statuses.fetch(:cancelled),
            updated_at: now
          )
        end

        AuthenticationToken.where(
          project_invitation_id: invitations.map(&:id),
          purpose: AuthenticationToken.purposes.fetch(:invitation)
        ).order(:id).lock.each do |token|
          token.transition_to!(:cancelled, at: now) if token.outstanding?
        end

        Result.new(status: :cancelled, invitations: invitations.freeze)
      end

      private

      def ensure_transaction!
        return if ApplicationRecord.connection.transaction_open?

        raise OutsideTransaction, "issuer invitation cancellation requires an open outer transaction"
      end

      def validate_scope!(issuer, scope)
        valid = issuer&.persisted? && scope.is_a?(LockScope) && scope.issuer_id == issuer.id
        raise InvalidScope, "issuer invitation cancellation scope is invalid" unless valid
      end
    end
  end
end
