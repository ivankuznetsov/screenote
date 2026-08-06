# frozen_string_literal: true

module UserAuthenticationLinks
  class Consume
    PURPOSES = %i[password_reset magic_link email_confirmation].freeze

    Result = Data.define(:status, :user, :errors, :newly_confirmed) do
      def initialize(status:, user: nil, errors: {}, newly_confirmed: false)
        safe_errors = errors.each_with_object({}) do |(attribute, messages), copy|
          copy[attribute.to_sym] = Array(messages).map(&:to_s).freeze
        end.freeze
        super(
          status: status.to_sym,
          user: status.to_sym == :consumed ? user : nil,
          errors: safe_errors,
          newly_confirmed: status.to_sym == :consumed && newly_confirmed == true
        )
      end

      def consumed?
        status == :consumed
      end

      def inspect
        "#<#{self.class.name} status=#{status.inspect} user_id=#{user&.id.inspect} " \
          "error_attributes=#{errors.keys.inspect}>"
      end
    end

    class LostRace < StandardError; end

    class << self
      def call(token_id:, purpose:, **options)
        new(token_id:, purpose:, **options).call
      end
    end

    def initialize(
      token_id:,
      purpose:,
      attributes: {},
      resolver: AuthenticationLinks::Resolver.new(keyring: AuthenticationLinks::Runtime.keyring),
      clock: -> { Time.current },
      reconfirmation_checker: ->(user) { user.reconfirming? }
    )
      @token_id = Integer(token_id, exception: false)
      @purpose = purpose.to_sym
      @attributes = attributes.to_h.symbolize_keys.slice(:password, :password_confirmation)
      @resolver = resolver
      @clock = clock
      @reconfirmation_checker = reconfirmation_checker
    end

    def call
      return result(:invalid) unless token_id&.positive? && PURPOSES.include?(purpose)

      subject_id = AuthenticationToken.where(id: token_id).pick(:user_id)
      return result(:invalid) unless subject_id

      DatabaseRetry.call do
        AuthenticationToken.transaction do
          user = User.find_by(id: subject_id)
          next result(:invalid) unless user

          user = AuthorityLock.user!(user)
          token = AuthenticationToken.lock.find_by(id: token_id)
          next result(:invalid) unless token&.user_id == user.id

          resolution = resolver.revalidate(token_id: token.id, expected_purpose: purpose)
          next result(resolution.status) unless resolution.valid?
          next result(:inactive_user) unless user.access_active?
          if %i[magic_link email_confirmation].include?(purpose) && reconfirmation_checker.call(user)
            unless token.transition_to!(:cancelled, at: clock.call)
              raise LostRace, "authentication link changed during reconfirmation rejection"
            end
            next result(:reconfirmation_unsupported)
          end

          newly_confirmed = user.unconfirmed?
          operation_result = apply_operation(user)
          next operation_result unless operation_result == true

          unless token.transition_to!(:consumed, at: clock.call)
            raise LostRace, "authentication link was consumed concurrently"
          end

          result(:consumed, user: user, newly_confirmed: newly_confirmed && user.confirmed?)
        end
      end
    rescue LostRace
      resolution = resolver.revalidate(token_id: token_id, expected_purpose: purpose)
      result(resolution.status)
    rescue DatabaseRetry::Exhausted
      result(:retryable_busy)
    rescue ActiveRecord::ActiveRecordError
      result(:unavailable)
    end

    private

    attr_reader :attributes, :clock, :purpose, :reconfirmation_checker, :resolver, :token_id

    def apply_operation(user)
      case purpose
      when :password_reset
        missing = %i[password password_confirmation].select { |key| attributes[key].blank? }
        unless missing.empty?
          errors = missing.to_h { |key| [ key, "can't be blank" ] }
          return result(:validation_failed, errors: errors)
        end
        return result(:validation_failed, errors: user.errors.to_hash) unless user.update(attributes)

        user.sessions.delete_all
      when :magic_link, :email_confirmation
        return result(:validation_failed, errors: user.errors.to_hash) unless user.confirm!
      end

      true
    end

    def result(status, user: nil, errors: {}, newly_confirmed: false)
      Result.new(status:, user:, errors:, newly_confirmed:)
    end
  end
end
