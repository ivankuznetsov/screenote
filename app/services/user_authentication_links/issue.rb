# frozen_string_literal: true

module UserAuthenticationLinks
  class Issue
    PURPOSES = {
      password_reset: -> { RailsSimpleAuth.configuration.password_reset_expiry },
      magic_link: -> { RailsSimpleAuth.configuration.magic_link_expiry },
      email_confirmation: -> { RailsSimpleAuth.configuration.confirmation_expiry }
    }.freeze
    MAILER_METHODS = {
      password_reset: :password_reset,
      magic_link: :magic_link,
      email_confirmation: :confirmation
    }.freeze

    Result = Data.define(:status, :token) do
      def initialize(status:, token: nil)
        super(status: status.to_sym, token: status.to_sym == :issued ? token : nil)
      end

      def issued?
        status == :issued
      end

      def inspect
        "#<#{self.class.name} status=#{status.inspect} token_id=#{token&.id.inspect}>"
      end
    end

    class << self
      def call(user:, purpose:, **options)
        new(user:, purpose:, **options).call
      end
    end

    def initialize(
      user:,
      purpose:,
      deployment: Screenote::Deployment.current,
      issuer: nil,
      enqueue: true,
      clock: -> { Time.current }
    )
      @user_id = user&.id
      @purpose = purpose.to_sym
      @deployment = deployment
      @issuer = issuer || AuthenticationLinks::Issuer.new(
        origin: AuthenticationLinks::Runtime.origin,
        keyring: AuthenticationLinks::Runtime.keyring,
        clock: clock
      )
      @enqueue = enqueue
      @clock = clock
    end

    def call
      return result(:mail_disabled) unless deployment.mail?
      return result(:invalid) unless PURPOSES.key?(purpose) && user_id.is_a?(Integer)

      issued = DatabaseRetry.call do
        User.transaction do
          user = User.find_by(id: user_id)
          next result(:not_found) unless user

          user = AuthorityLock.user!(user)
          next result(:inactive_user) unless user.access_active?
          next result(:not_eligible) if purpose == :password_reset && user.unconfirmed?
          if %i[magic_link email_confirmation].include?(purpose) && user.reconfirming?
            next result(:reconfirmation_unsupported)
          end

          issuance = issuer.call(
            purpose: purpose,
            subject: user,
            expires_at: clock.call + PURPOSES.fetch(purpose).call
          )
          result(:issued, token: issuance.token)
        end
      end

      enqueue_delivery(issued.token) if issued.issued? && enqueue
      issued
    rescue DatabaseRetry::Exhausted
      result(:retryable_busy)
    rescue ActiveRecord::ActiveRecordError, AuthenticationLinks::Issuer::Error
      result(:unavailable)
    end

    private

    attr_reader :clock, :deployment, :enqueue, :issuer, :purpose, :user_id

    def enqueue_delivery(token)
      UserMailer.public_send(MAILER_METHODS.fetch(purpose), user_id, token.id).deliver_later
    end

    def result(status, token: nil)
      Result.new(status:, token:)
    end
  end
end
