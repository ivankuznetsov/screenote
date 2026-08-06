# frozen_string_literal: true

module ProjectInvitations
  class Cancel
    Result = Data.define(:status, :invitation) do
      def success?
        status == :cancelled
      end
    end

    class << self
      def call(principal:, project:, invitation_id:, clock: -> { Time.current })
        new(
          principal: principal,
          project_id: project&.id,
          invitation_id: invitation_id,
          clock: clock
        ).call
      end
    end

    def initialize(principal:, project_id:, invitation_id:, clock:)
      @principal = principal
      @project_id = project_id
      @invitation_id = Integer(invitation_id, exception: false)
      @clock = clock
    end

    def call
      return result(:not_found) unless project_id.present? && invitation_id&.positive?

      DatabaseRetry.call do
        ProjectInvitation.transaction { cancel_in_transaction }
      end
    rescue DatabaseRetry::Exhausted
      result(:retryable_busy)
    end

    private

    attr_reader :principal, :project_id, :invitation_id, :clock

    def cancel_in_transaction
      invitation_hint = ProjectInvitation.find_by(id: invitation_id, project_id: project_id)
      return result(:not_found) unless invitation_hint

      email = AdmissionLock.email!(invitation_hint.email)
      actor = principal&.user
      project_creator_id = Project.where(id: project_id).pick(:user_id)
      invited_user_id = User.where(email: email).pick(:id)
      users = User.where(
        id: [ actor&.id, project_creator_id, invitation_hint.inviter_id, invited_user_id ].compact
      ).to_a
      locked_users = AuthorityLock.users!(users).index_by(&:id)
      locked_actor = locked_users[actor&.id]

      project = Project.lock.find_by(id: project_id)
      return result(:not_found) unless project && project.user_id == project_creator_id

      invitation = ProjectInvitation.lock.find_by(id: invitation_id, project_id: project.id)
      return result(:not_found) unless invitation && invitation.email == email

      memberships = ProjectMembership.where(project_id: project.id).order(:id).lock.to_a
      return result(:forbidden, invitation: invitation) unless authorized_owner?(locked_actor, memberships)

      tokens = AuthenticationToken.where(
        project_invitation_id: invitation.id,
        purpose: AuthenticationToken.purposes.fetch(:invitation)
      ).order(:id).lock.to_a

      if invitation.accepted?
        tokens.each { |token| token.transition_to!(:consumed, at: current_time) if token.outstanding? }
        result(:already_accepted, invitation: invitation)
      elsif invitation.cancelled?
        tokens.each { |token| token.transition_to!(:cancelled, at: current_time) if token.outstanding? }
        result(:already_cancelled, invitation: invitation)
      else
        invitation.update_columns(
          status: ProjectInvitation.statuses.fetch(:cancelled),
          updated_at: current_time
        )
        tokens.each { |token| token.transition_to!(:cancelled, at: current_time) if token.outstanding? }
        result(:cancelled, invitation: invitation)
      end
    end

    def authorized_owner?(actor, memberships)
      actor&.active? && principal.is_a?(AuthenticatedPrincipal) && principal.user_principal? &&
        principal.write? &&
        memberships.any? { |membership| membership.user_id == actor.id && membership.owner? }
    end

    def current_time
      clock.call.to_time
    end

    def result(status, invitation: nil)
      Result.new(status: status, invitation: invitation)
    end
  end
end
