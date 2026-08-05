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
        User.transaction do
          locked_actor = AuthorityLock.user!(actor)
          locked_project = Project.lock.find_by(id: project&.id)

          remove_locked(
            project: locked_project,
            membership_id: membership_id,
            actor: locked_actor
          )
        end
      rescue ActiveRecord::RecordNotFound
        Result.new(status: :forbidden, membership: nil)
      end

      private

      def remove_locked(project:, membership_id:, actor:)
        return Result.new(status: :forbidden, membership: nil) unless project && actor

        actor_membership = ProjectMembership.lock.find_by(project_id: project.id, user_id: actor.id)
        return Result.new(status: :forbidden, membership: nil) unless actor_membership&.owner?

        membership = ProjectMembership.lock.find_by(project_id: project.id, id: membership_id)
        return Result.new(status: :not_found, membership: nil) unless membership
        return Result.new(status: :cannot_remove_self, membership: membership) if membership.user_id == actor.id

        if membership.destroy
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
