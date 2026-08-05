# frozen_string_literal: true

module Oauth
  class PrincipalBinding
    class << self
      def valid?(credential)
        return false unless credential

        user = User.find_by(id: credential.resource_owner_id)
        return false unless active_user?(user)

        case credential.principal_kind
        when "user"
          credential.project_id.nil?
        when "project"
          credential.project_id.present? &&
            ProjectMembership.exists?(user_id: user.id, project_id: credential.project_id)
        else
          false
        end
      end

      # Serializes authority changes and credential issuance in one order:
      # resource owner -> project -> membership -> credential.
      #
      # The block always runs while the relevant authority rows are locked and
      # receives whether the binding is still valid (plus the locked membership
      # for project selection). Callers must not issue a credential when valid
      # is false.
      def with_locked_credential(credential, &block)
        user = User.find_by(id: credential&.resource_owner_id)

        case credential&.principal_kind
        when "user"
          with_locked_user_credential(user, credential, &block)
        when "project"
          with_locked_project(user: user, project_id: credential.project_id, credential: credential, &block)
        else
          lock_credential_without_authority(credential, &block)
        end
      end

      # Used while a browser consent/device request is selecting a project,
      # before the project-scoped credential has been created or updated.
      def with_locked_project(user:, project_id:, credential: nil)
        User.transaction do
          locked_user = lock_user(user)
          project = Project.lock.find_by(id: project_id)
          membership = if locked_user && project
            ProjectMembership.lock.find_by(user_id: locked_user.id, project_id: project.id)
          end
          credential_locked = credential.nil? || lock_credential(credential)

          valid = active_user?(locked_user) && project.present? && membership.present? && credential_locked
          yield(valid, membership)
        end
      end

      private

      def with_locked_user_credential(user, credential)
        User.transaction do
          locked_user = lock_user(user)
          credential_locked = lock_credential(credential)
          valid = active_user?(locked_user) && credential&.project_id.nil? && credential_locked

          yield(valid)
        end
      end

      def lock_credential_without_authority(credential)
        ApplicationRecord.transaction do
          lock_credential(credential)
          yield(false)
        end
      end

      def lock_user(user)
        AuthorityLock.user!(user) if user
      rescue ActiveRecord::RecordNotFound
        nil
      end

      def lock_credential(credential)
        return false unless credential

        credential.lock!
        true
      rescue ActiveRecord::RecordNotFound
        false
      end

      def active_user?(user)
        user.present? && (!user.respond_to?(:active?) || user.active?)
      end
    end
  end
end
