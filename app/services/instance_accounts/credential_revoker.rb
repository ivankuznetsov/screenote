# frozen_string_literal: true

module InstanceAccounts
  class CredentialRevoker
    LockSet = Data.define(
      :target,
      :projects,
      :invitation_scope,
      :memberships,
      :sessions,
      :oauth_grants,
      :oauth_tokens,
      :device_grants,
      :api_keys,
      :authentication_tokens
    )

    Result = Data.define(
      :sessions,
      :oauth_grants,
      :oauth_tokens,
      :device_grants,
      :api_keys,
      :authentication_tokens,
      :invitations
    ) do
      def as_json(*)
        to_h.transform_keys(&:to_s)
      end
    end

    class << self
      def lock!(target:)
        ensure_transaction!
        project_ids = credential_project_ids(target)
        projects = Project.where(id: project_ids).order(:id).lock.to_a
        invitation_scope = ProjectInvitations::CancelForIssuer.lock_scope!(
          issuer: target,
          projects: projects
        )
        memberships = ProjectMembership.where(project_id: projects.map(&:id)).order(:id).lock.to_a

        sessions = Session.where(user_id: target.id).order(:id).lock.to_a
        oauth_grants = Doorkeeper::AccessGrant.where(resource_owner_id: target.id, revoked_at: nil)
          .order(:id).lock.to_a
        oauth_tokens = Doorkeeper::AccessToken.where(resource_owner_id: target.id, revoked_at: nil)
          .order(:id).lock.to_a
        device_grants = OauthDeviceGrant.where(resource_owner_id: target.id).order(:id).lock.to_a
        api_keys = ApiKey.active.where(issued_by_user_id: target.id).order(:id).lock.to_a
        authentication_tokens = authentication_token_scope(target, invitation_scope).order(:id).lock.to_a

        LockSet.new(
          target: target,
          projects: projects.freeze,
          invitation_scope: invitation_scope,
          memberships: memberships.freeze,
          sessions: sessions.freeze,
          oauth_grants: oauth_grants.freeze,
          oauth_tokens: oauth_tokens.freeze,
          device_grants: device_grants.freeze,
          api_keys: api_keys.freeze,
          authentication_tokens: authentication_tokens.freeze
        )
      end

      def revoke!(lock_set, at: Time.current, preserve_authentication_token_id: nil)
        ensure_transaction!
        now = at.to_time
        cancellation = ProjectInvitations::CancelForIssuer.call(
          issuer: lock_set.target,
          scope: lock_set.invitation_scope,
          clock: -> { now }
        )

        Session.where(id: lock_set.sessions.map(&:id)).delete_all
        Doorkeeper::AccessGrant.where(id: lock_set.oauth_grants.map(&:id))
          .update_all(revoked_at: now)
        Doorkeeper::AccessToken.where(id: lock_set.oauth_tokens.map(&:id))
          .update_all(revoked_at: now)
        OauthDeviceGrant.where(id: lock_set.device_grants.map(&:id)).delete_all
        ApiKey.where(id: lock_set.api_keys.map(&:id)).update_all(revoked_at: now)

        transitioned = 0
        lock_set.authentication_tokens.each do |token|
          next if token.id == preserve_authentication_token_id
          next unless token.outstanding?

          transitioned += 1 if token.transition_to!(:cancelled, at: now)
        end

        Result.new(
          sessions: lock_set.sessions.size,
          oauth_grants: lock_set.oauth_grants.size,
          oauth_tokens: lock_set.oauth_tokens.size,
          device_grants: lock_set.device_grants.size,
          api_keys: lock_set.api_keys.size,
          authentication_tokens: transitioned,
          invitations: cancellation.invitations.size
        )
      end

      private

      def credential_project_ids(target)
        ids = ProjectInvitation.pending.where(inviter_id: target.id).pluck(:project_id)
        ids.concat(ApiKey.active.where(issued_by_user_id: target.id).pluck(:project_id))
        ids.concat(Doorkeeper::AccessGrant.where(resource_owner_id: target.id, revoked_at: nil)
          .where.not(project_id: nil).pluck(:project_id))
        ids.concat(Doorkeeper::AccessToken.where(resource_owner_id: target.id, revoked_at: nil)
          .where.not(project_id: nil).pluck(:project_id))
        ids.concat(OauthDeviceGrant.where(resource_owner_id: target.id)
          .where.not(project_id: nil).pluck(:project_id))
        ids.compact.uniq.sort
      end

      def authentication_token_scope(target, invitation_scope)
        subject_tokens = AuthenticationToken.where(user_id: target.id)
          .or(AuthenticationToken.where(issued_by_user_id: target.id))
        invitation_ids = invitation_scope.invitations.map(&:id)
        return subject_tokens if invitation_ids.empty?

        subject_tokens.or(AuthenticationToken.where(project_invitation_id: invitation_ids))
      end

      def ensure_transaction!
        return if ApplicationRecord.connection.transaction_open?

        raise "credential revocation requires an open outer transaction"
      end
    end
  end
end
