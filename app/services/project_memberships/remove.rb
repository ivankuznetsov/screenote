# frozen_string_literal: true

module ProjectMemberships
  class Remove
    Result = Data.define(:status, :membership) do
      def success?
        status == :removed
      end
    end

    class << self
      def call(project:, membership_id:, actor:)
        DatabaseRetry.call do
          target_user = target_user_for(project: project, membership_id: membership_id)

          User.transaction do
            locked_users = AuthorityLock.users!(actor, *Array(target_user)).index_by(&:id)
            locked_actor = locked_users.fetch(actor.id)
            locked_target = target_user && locked_users.fetch(target_user.id)
            locked_project = Project.lock.find_by(id: project&.id)
            cancellation_scope = cancellation_scope_for(locked_target, locked_project)
            memberships = locked_project ?
              ProjectMembership.where(project_id: locked_project.id).order(:id).lock.to_a : []

            remove_locked(
              project: locked_project,
              membership_id: membership_id,
              actor: locked_actor,
              target_user: locked_target,
              memberships: memberships,
              cancellation_scope: cancellation_scope
            )
          end
        end
      rescue DatabaseRetry::Exhausted
        Result.new(status: :retryable_busy, membership: nil)
      rescue ActiveRecord::RecordNotFound
        Result.new(status: :forbidden, membership: nil)
      end

      private

      def target_user_for(project:, membership_id:)
        user_id = ProjectMembership.where(project_id: project&.id, id: membership_id).pick(:user_id)
        User.find_by(id: user_id) if user_id
      end

      def cancellation_scope_for(target_user, project)
        return unless target_user && project

        ProjectInvitations::CancelForIssuer.lock_scope!(issuer: target_user, projects: [ project ])
      end

      def remove_locked(project:, membership_id:, actor:, target_user:, memberships:, cancellation_scope:)
        return Result.new(status: :forbidden, membership: nil) unless project && actor.active?

        actor_membership = memberships.find { |candidate| candidate.user_id == actor.id }
        return Result.new(status: :forbidden, membership: nil) unless actor_membership&.owner?

        membership = memberships.find { |candidate| candidate.id.to_s == membership_id.to_s }
        return Result.new(status: :not_found, membership: nil) unless membership && target_user
        return Result.new(status: :not_found, membership: nil) unless membership.user_id == target_user.id
        return Result.new(status: :cannot_remove_self, membership: membership) if membership.user_id == actor.id

        if membership.destroy
          ProjectInvitations::CancelForIssuer.call(issuer: target_user, scope: cancellation_scope)
          revoke_credentials!(project: project, user_id: membership.user_id)
          Result.new(status: :removed, membership: membership)
        else
          Result.new(status: :invalid, membership: membership)
        end
      end

      def revoke_credentials!(project:, user_id:)
        revoked_at = Time.current

        Doorkeeper::AccessGrant.where(
          project_id: project.id,
          resource_owner_id: user_id,
          revoked_at: nil
        ).update_all(revoked_at: revoked_at)
        Doorkeeper::AccessToken.where(
          project_id: project.id,
          resource_owner_id: user_id,
          revoked_at: nil
        ).update_all(revoked_at: revoked_at)
        OauthDeviceGrant.where(project_id: project.id, resource_owner_id: user_id).delete_all
        ApiKey.active.where(project_id: project.id, issued_by_user_id: user_id).update_all(revoked_at: revoked_at)
      end
    end
  end
end
