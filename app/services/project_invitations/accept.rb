# frozen_string_literal: true

module ProjectInvitations
  class Accept
    Result = Data.define(:status, :invitation, :user, :project, :errors) do
      def success?
        status == :accepted
      end
    end

    class RollbackResult < StandardError
      attr_reader :result

      def initialize(result)
        @result = result
        super("invitation acceptance rolled back")
      end
    end

    class << self
      def call(
        token_id:,
        proof:,
        resolver: nil,
        deployment: Screenote::Deployment.current,
        clock: -> { Time.current }
      )
        resolver ||= AuthenticationLinks::Resolver.new(keyring: AuthenticationLinks::Runtime.keyring, clock: clock)
        new(
          token_id: token_id,
          proof: proof,
          resolver: resolver,
          deployment: deployment,
          clock: clock
        ).call
      end
    end

    def initialize(token_id:, proof:, resolver:, deployment:, clock:)
      @token_id = token_id
      @proof = proof
      @resolver = resolver
      @deployment = deployment
      @clock = clock
    end

    def call
      return result(:authentication_required) unless proof
      return result(invalid_proof_status) unless proof.is_a?(IdentityProof) && proof.valid?
      return result(:invalid) unless token_id.is_a?(Integer) && token_id.positive?

      preflight = resolver.revalidate(token_id: token_id, expected_purpose: :invitation)
      return token_result(preflight) unless preflight.valid?

      DatabaseRetry.call do
        begin
          ProjectInvitation.transaction do
            accept_in_transaction(preflight.token.project_invitation_id)
          end
        rescue RollbackResult => rollback
          rollback.result
        end
      end
    rescue DatabaseRetry::Exhausted
      result(:retryable_busy)
    rescue ActiveRecord::RecordInvalid => error
      result(:invalid, errors: error.record.errors.full_messages)
    rescue ActiveRecord::RecordNotUnique
      result(provider_identity_collision_status)
    end

    private

    attr_reader :token_id, :proof, :resolver, :deployment, :clock

    def accept_in_transaction(invitation_id)
      invitation_hint = ProjectInvitation.find_by(id: invitation_id)
      return result(:invalid) unless invitation_hint

      email = AdmissionLock.email!(invitation_hint.email)
      hints = authority_hints(invitation_hint, email)
      locked_users = AuthorityLock.users!(hints.fetch(:users)).index_by(&:id)
      candidate = identity_candidate(email, hints, locked_users)
      if candidate.is_a?(Result)
        return result(
          candidate.status,
          invitation: invitation_hint,
          project: invitation_hint.project,
          errors: candidate.errors
        )
      end

      candidate_was_created = candidate.new_record?
      candidate.save! if candidate_was_created

      project = Project.lock.find_by(id: invitation_hint.project_id)
      rollback_with(result(:invalid)) unless project && project.user_id == hints.fetch(:project_creator_id)

      invitation = ProjectInvitation.lock.find_by(id: invitation_id, project_id: project.id)
      rollback_with(result(:invalid)) unless invitation && invitation.email == email
      rollback_with(result(:invalid)) unless locked_users.key?(invitation.inviter_id)

      memberships = ProjectMembership.where(project_id: project.id).order(:id).lock.to_a

      inviter = locked_users[invitation.inviter_id]
      unless active_owner?(inviter, memberships)
        discard_provisional_user(candidate, candidate_was_created)
        locked_token = lock_exact_token(invitation)
        invitation.update_columns(
          status: ProjectInvitation.statuses.fetch(:cancelled),
          updated_at: current_time
        )
        locked_token.transition_to!(:cancelled, at: current_time) if locked_token&.outstanding?
        return result(:issuer_revoked, invitation: invitation, project: project)
      end

      existing_membership = memberships.find { |membership| membership.user_id == candidate.id }
      if existing_membership.nil? && member_limit_reached?(project, locked_users, memberships)
        rollback_with(result(:limit_reached, invitation: invitation, user: candidate, project: project))
      end

      if invitation.cancelled?
        discard_provisional_user(candidate, candidate_was_created)
        return finish_cancelled(invitation, lock_exact_token(invitation), project)
      elsif invitation.accepted?
        discard_provisional_user(candidate, candidate_was_created)
        return finish_already_used(invitation, lock_exact_token(invitation), project)
      end

      ProjectMembership.create!(project: project, user: candidate, role: :member) unless existing_membership

      locked_token = lock_exact_token(invitation)
      rollback_with(result(:invalid, invitation: invitation, project: project)) unless locked_token

      resolution = resolver.revalidate(token_id: locked_token.id, expected_purpose: :invitation)
      rollback_with(token_result(resolution, invitation: invitation, project: project)) unless resolution.valid?

      invitation.update_columns(
        status: ProjectInvitation.statuses.fetch(:accepted),
        updated_at: current_time
      )
      unless locked_token.transition_to!(:consumed, at: current_time)
        latest = resolver.revalidate(token_id: locked_token.id, expected_purpose: :invitation)
        status = latest.valid? ? :retryable_busy : latest.status
        rollback_with(result(status, invitation: invitation, user: candidate, project: project))
      end

      result(:accepted, invitation: invitation, user: candidate, project: project)
    end

    def authority_hints(invitation, email)
      invited_user = User.find_by(email: email)
      proof_user = User.find_by(id: proof.user_id) if proof.session?
      provider_user = if proof.provider?
        User.find_by(oauth_provider: proof.provider_name, oauth_uid: proof.provider_uid)
      end
      project_creator_id = Project.where(id: invitation.project_id).pick(:user_id)
      users = User.where(
        id: [
          invitation.inviter_id,
          project_creator_id,
          invited_user&.id,
          proof_user&.id,
          provider_user&.id
        ].compact
      ).to_a

      {
        users: users,
        invited_user_id: invited_user&.id,
        proof_user_id: proof_user&.id,
        provider_user_id: provider_user&.id,
        project_creator_id: project_creator_id
      }
    end

    def identity_candidate(email, hints, locked_users)
      invited_user = locked_users[hints[:invited_user_id]]

      if proof.session?
        session_user = locked_users[hints[:proof_user_id]]
        return result(:invalid_identity) unless session_user&.active?
        return result(:identity_mismatch) unless session_user.email == email

        session_user
      elsif proof.local?
        local_candidate(email, invited_user)
      else
        provider_candidate(email, invited_user, hints, locked_users)
      end
    end

    def local_candidate(email, invited_user)
      if invited_user
        return result(:invalid_identity) unless invited_user.active?
        result(:authentication_required)
      else
        candidate = User.new(
          email: email,
          password: proof.password,
          password_confirmation: proof.password_confirmation,
          confirmed_at: current_time,
          access_status: :active
        )
        return result(:invalid_input, errors: candidate.errors.full_messages) unless candidate.valid?

        candidate
      end
    end

    def provider_candidate(email, invited_user, hints, locked_users)
      return result(:identity_mismatch) unless proof.verified_email == email

      provider_user = locked_users[hints[:provider_user_id]]
      if provider_user
        return result(:invalid_identity) unless provider_user.active?
        return result(:identity_mismatch) unless provider_user.email == email

        provider_user
      elsif invited_user
        result(:invalid_identity)
      else
        candidate = User.new(
          email: email,
          password: SecureRandom.base64(32),
          confirmed_at: current_time,
          access_status: :active,
          oauth_provider: proof.provider_name,
          oauth_uid: proof.provider_uid
        )
        candidate
      end
    end

    def active_owner?(user, memberships)
      user.active? && memberships.any? do |membership|
        membership.user_id == user.id && membership.owner?
      end
    end

    def member_limit_reached?(project, locked_users, memberships)
      return false unless deployment.billing?

      creator = locked_users.fetch(project.user_id)
      return false if creator.pro?(deployment: deployment)

      memberships.count(&:member?) >= Subscription::FREE_MEMBER_LIMIT
    end

    def finish_cancelled(invitation, token, project)
      token.transition_to!(:cancelled, at: current_time) if token&.outstanding?
      result(:cancelled, invitation: invitation, project: project)
    end

    def finish_already_used(invitation, token, project)
      token.transition_to!(:consumed, at: current_time) if token&.outstanding?
      result(:already_used, invitation: invitation, project: project)
    end

    def lock_exact_token(invitation)
      AuthenticationToken.lock.find_by(
        id: token_id,
        project_invitation_id: invitation.id,
        purpose: AuthenticationToken.purposes.fetch(:invitation)
      )
    end

    def discard_provisional_user(candidate, candidate_was_created)
      candidate.delete if candidate_was_created && candidate.persisted?
    end

    def rollback_with(rollback_result)
      raise RollbackResult, rollback_result
    end

    def token_result(resolution, invitation: nil, project: nil)
      status = resolution.status
      invitation ||= resolution.token&.project_invitation
      project ||= invitation&.project
      result(status, invitation: invitation, project: project)
    end

    def invalid_proof_status
      proof.is_a?(IdentityProof) && proof.local? ? :invalid_input : :invalid_identity
    end

    def provider_identity_collision_status
      return :invalid unless proof.is_a?(IdentityProof) && proof.provider?

      user = User.find_by(oauth_provider: proof.provider_name, oauth_uid: proof.provider_uid)
      user&.email == proof.verified_email ? :retryable_busy : :identity_mismatch
    end

    def current_time
      clock.call.to_time
    end

    def result(status, invitation: nil, user: nil, project: nil, errors: [])
      Result.new(
        status: status,
        invitation: invitation,
        user: user,
        project: project,
        errors: errors.freeze
      )
    end
  end
end
