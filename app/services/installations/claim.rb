# frozen_string_literal: true

module Installations
  class Claim
    AUDIT_EVENT_TYPE = "installation_claimed"
    CHANNEL_PATTERN = /\A[a-z0-9_]{1,32}\z/

    Result = Data.define(:status, :user, :errors) do
      def initialize(status:, user: nil, errors: {})
        safe_errors = errors.each_with_object({}) do |(attribute, messages), copy|
          copy[attribute.to_sym] = Array(messages).map(&:to_s).freeze
        end.freeze

        super(
          status: status.to_sym,
          user: status.to_sym == :claimed ? user : nil,
          errors: safe_errors
        )
      end

      def claimed?
        status == :claimed
      end

      def inspect
        "#<#{self.class.name} status=#{status.inspect} user_id=#{user&.id.inspect} " \
          "error_attributes=#{errors.keys.inspect}>"
      end

      alias_method :to_s, :inspect

      def as_json(*)
        {
          "status" => status.to_s,
          "user_id" => user&.id,
          "error_attributes" => errors.keys.map(&:to_s)
        }
      end
    end

    class << self
      def call(email:, password:, password_confirmation:, channel: "web")
        new(
          email:,
          password:,
          password_confirmation:,
          channel:
        ).call
      end
    end

    def initialize(email:, password:, password_confirmation:, channel:)
      @email = email
      @password = password
      @password_confirmation = password_confirmation
      @channel = normalized_channel(channel)
      @normalized_email = nil
    end

    def call
      DatabaseRetry.call do
        Installation.transaction do
          installation = Installation.lock.find_by(singleton_key: Installation::SINGLETON_KEY)
          next result(:unavailable) unless valid_self_hosted_installation?(installation)
          next result(:already_claimed) if installation.claimed?

          @normalized_email = AdmissionLock.email!(email)
          existing_users = User.where(email: normalized_email).order(:id).lock.load
          if existing_users.any?
            next result(:email_taken, errors: { email: "has already been taken" })
          end

          administrator = create_administrator!
          claim_installation!(installation, administrator)
          append_audit_event!(installation, administrator)

          result(:claimed, user: administrator)
        end
      end
    rescue ArgumentError => error
      raise unless error.message == "email must be present"

      result(:invalid, errors: { email: "can't be blank" })
    rescue ActiveRecord::RecordInvalid => error
      result(:invalid, errors: errors_for(error.record))
    rescue ActiveRecord::RecordNotUnique => error
      if normalized_email && user_email_unique_violation?(error) && User.exists?(email: normalized_email)
        result(:email_taken, errors: { email: "has already been taken" })
      else
        result(:unavailable)
      end
    rescue DatabaseRetry::Exhausted
      result(:retryable_busy)
    rescue ActiveRecord::ActiveRecordError
      result(:unavailable)
    end

    def inspect
      "#<#{self.class.name} channel=#{channel.inspect}>"
    end

    alias_method :to_s, :inspect

    def as_json(*)
      { "operation" => self.class.name, "channel" => channel }
    end

    private

    attr_reader :channel, :email, :normalized_email, :password, :password_confirmation

    def valid_self_hosted_installation?(installation)
      installation&.persisted? && installation.valid? && installation.self_hosted? &&
        (installation.unclaimed? || installation.claimed?)
    end

    def create_administrator!
      User.create!(
        email: normalized_email,
        password:,
        password_confirmation:,
        confirmed_at: Time.current,
        access_status: :active
      )
    end

    def claim_installation!(installation, administrator)
      attributes = {
        state: "claimed",
        administrator:,
        claimed_at: Time.current,
        bootstrap_token_digest: nil
      }
      installation.update!(attributes)
    end

    def append_audit_event!(installation, administrator)
      InstallationAuditEvent.create!(
        installation:,
        actor_user: administrator,
        target_user: administrator,
        event_type: AUDIT_EVENT_TYPE,
        metadata: { "channel" => channel }
      )
    end

    def normalized_channel(value)
      normalized = value.to_s.strip.downcase
      CHANNEL_PATTERN.match?(normalized) ? normalized : "unknown"
    end

    def result(status, user: nil, errors: {})
      Result.new(status:, user:, errors:)
    end

    def errors_for(record)
      return {} unless record.respond_to?(:errors)

      record.errors.to_hash
    end

    def user_email_unique_violation?(error)
      error.message.match?(/(?:users.*email|index_users_on_(?:normalized_)?email)/i)
    end
  end
end
