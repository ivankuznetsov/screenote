# frozen_string_literal: true

module ProjectInvitations
  class Issue
    EXPIRY = 7.days
    SUCCESS_STATUSES = %i[issued already_pending reissued].freeze

    Result = Data.define(:status, :invitation, :token, :presentation, :delivery_status, :errors) do
      def success?
        SUCCESS_STATUSES.include?(status)
      end
    end

    class << self
      def call(
        principal:,
        project:,
        email:,
        authentication_link_issuer: nil,
        deployment: Screenote::Deployment.current,
        clock: -> { Time.current },
        expires_at: nil,
        mailer: ProjectInvitationMailer
      )
        authentication_link_issuer ||= AuthenticationLinks::Issuer.new(
          origin: AuthenticationLinks::Runtime.origin,
          keyring: AuthenticationLinks::Runtime.keyring,
          clock: clock
        )

        new(
          principal: principal,
          project: project,
          email: email,
          authentication_link_issuer: authentication_link_issuer,
          deployment: deployment,
          clock: clock,
          expires_at: expires_at,
          mailer: mailer
        ).call
      end
    end

    def initialize(
      principal:,
      project:,
      email:,
      authentication_link_issuer:,
      deployment:,
      clock:,
      expires_at:,
      mailer:
    )
      @principal = principal
      @project_id = project&.id
      @email = normalize_email(email)
      @authentication_link_issuer = authentication_link_issuer
      @deployment = deployment
      @clock = clock
      @expires_at = expires_at
      @mailer = mailer
    end

    def call
      return result(:invalid) unless valid_input?
      return result(:not_found) unless project_id.present?

      issued_result = DatabaseRetry.call do
        ProjectInvitation.transaction { issue_in_transaction }
      end
      issued_result.with(delivery_status: enqueue_mail(issued_result))
    rescue DatabaseRetry::Exhausted
      result(:retryable_busy)
    rescue ActiveRecord::RecordInvalid => error
      result(:invalid, invitation: invitation_from(error), errors: validation_errors(error))
    rescue ActiveRecord::RecordNotUnique
      result(:invalid)
    end

    private

    attr_reader :principal, :project_id, :email, :authentication_link_issuer,
      :deployment, :clock, :expires_at, :mailer

    def issue_in_transaction
      AdmissionLock.email!(email)

      hints = authority_hints
      actor = hints.fetch(:actor)
      return result(:forbidden) unless actor

      locked_users = AuthorityLock.users!(hints.fetch(:users)).index_by(&:id)
      actor = locked_users.fetch(actor.id)
      return result(:inactive_issuer) unless actor.active?

      project = Project.lock.find_by(id: project_id)
      return result(:not_found) unless project
      return result(:not_found) unless locked_users.key?(project.user_id)

      invitations = ProjectInvitation
        .where(project_id: project.id, email: email)
        .order(:id)
        .lock
        .to_a
      return result(:not_found) unless invitation_issuers_locked?(invitations, locked_users)

      memberships = ProjectMembership.where(project_id: project.id).order(:id).lock.to_a
      return result(:forbidden) unless authorized_owner?(actor, memberships)

      invited_user = locked_users[hints[:invited_user]&.id]
      if invited_user && memberships.any? { |membership| membership.user_id == invited_user.id }
        return result(:already_member)
      end
      return result(:limit_reached) if member_limit_reached?(project, locked_users, memberships)

      pending = invitations.find(&:pending?)
      if pending && issuer_revoked?(pending, locked_users, memberships)
        cancel_invitation!(pending)
        cancel_tokens!(pending)
        pending = nil
      end

      if pending
        issue_or_represent(pending)
      else
        replacement = ProjectInvitation.create!(project: project, inviter: actor, email: email)
        issued = authentication_link_issuer.call(
          purpose: :invitation,
          subject: replacement,
          expires_at: token_expiry
        )
        status = invitations.any? ? :reissued : :issued
        result(
          status,
          invitation: replacement,
          token: issued.token,
          presentation: issued.presentation
        )
      end
    end

    def authority_hints
      actor = principal&.user
      project = Project.find_by(id: project_id)
      invited_user = User.find_by(email: email)
      inviter_ids = ProjectInvitation.where(project_id: project_id, email: email).distinct.pluck(:inviter_id)
      users = User.where(id: [ actor&.id, project&.user_id, invited_user&.id, *inviter_ids ].compact).to_a

      { actor: users.find { |user| user.id == actor&.id }, invited_user: invited_user, users: users }
    end

    def authorized_owner?(actor, memberships)
      principal.is_a?(AuthenticatedPrincipal) && principal.user_principal? && principal.write? &&
        memberships.any? do |membership|
          membership.user_id == actor.id && membership.owner?
        end
    end

    def invitation_issuers_locked?(invitations, locked_users)
      invitations.all? { |invitation| locked_users.key?(invitation.inviter_id) }
    end

    def issuer_revoked?(invitation, locked_users, memberships)
      inviter = locked_users.fetch(invitation.inviter_id)
      !inviter.active? || memberships.none? do |membership|
        membership.user_id == invitation.inviter_id && membership.owner?
      end
    end

    def member_limit_reached?(project, locked_users, memberships)
      return false unless deployment.billing?

      creator = locked_users.fetch(project.user_id)
      return false if creator.pro?(deployment: deployment)

      memberships.count(&:member?) >= Subscription::FREE_MEMBER_LIMIT
    end

    def issue_or_represent(invitation)
      tokens = AuthenticationToken.where(project_invitation_id: invitation.id, purpose: :invitation)
        .order(:id)
        .lock
        .to_a
      outstanding = tokens.find(&:outstanding?)

      if outstanding && outstanding.expires_at > current_time
        presentation = authentication_link_issuer.re_present(token: outstanding)
        return result(
          :already_pending,
          invitation: invitation,
          token: outstanding,
          presentation: presentation
        )
      end

      issued = authentication_link_issuer.call(
        purpose: :invitation,
        subject: invitation,
        expires_at: token_expiry
      )
      result(
        :reissued,
        invitation: invitation,
        token: issued.token,
        presentation: issued.presentation
      )
    end

    def cancel_invitation!(invitation)
      invitation.update_columns(
        status: ProjectInvitation.statuses.fetch(:cancelled),
        updated_at: current_time
      )
    end

    def cancel_tokens!(invitation)
      AuthenticationToken.where(project_invitation_id: invitation.id, purpose: :invitation)
        .order(:id)
        .lock
        .each do |token|
          token.transition_to!(:cancelled, at: current_time) if token.outstanding?
        end
    end

    def enqueue_mail(issued_result)
      return :not_requested unless deployment.mail?
      return :not_requested unless %i[issued reissued].include?(issued_result.status)

      mailer.invite(issued_result.invitation.id, issued_result.token.id).deliver_later
      :queued
    rescue StandardError => error
      Screenote::Monitoring.notify(
        error,
        context: { invitation_id: issued_result.invitation.id, authentication_token_id: issued_result.token.id }
      )
      :failed
    end

    def valid_input?
      email.present? && email.match?(URI::MailTo::EMAIL_REGEXP)
    end

    def normalize_email(value)
      value.to_s.strip.downcase.presence
    end

    def current_time
      clock.call.to_time
    end

    def token_expiry
      expires_at&.to_time || current_time + EXPIRY
    end

    def invitation_from(error)
      error.record if error.record.is_a?(ProjectInvitation)
    end

    def validation_errors(error)
      error.record.errors.full_messages.freeze
    end

    def result(status, invitation: nil, token: nil, presentation: nil, errors: [])
      Result.new(
        status: status,
        invitation: invitation,
        token: token,
        presentation: presentation,
        delivery_status: :not_requested,
        errors: errors.freeze
      )
    end
  end
end
