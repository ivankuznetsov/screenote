# frozen_string_literal: true

module ProjectInvitations
  class IdentityProof
    KINDS = %i[session local provider].freeze
    PROVIDERS = %w[google_oauth2 github].freeze

    class << self
      def session(user:)
        new(kind: :session, user_id: user&.id, valid: user&.persisted? == true)
      end

      def local(password:, password_confirmation: nil)
        password = password.to_s
        new(
          kind: :local,
          password: password,
          password_confirmation: password_confirmation&.to_s,
          valid: password.present?
        )
      end

      def provider(auth_hash)
        provider_name = value(auth_hash, "provider").to_s.strip.downcase
        provider_uid = value(auth_hash, "uid").to_s.strip
        info = value(auth_hash, "info") || {}
        verified_email = normalized_email(value(info, "email"))

        verified = case provider_name
        when "google_oauth2"
          value(info, "email_verified") == true
        when "github"
          github_email_verified?(auth_hash, verified_email)
        else
          false
        end

        valid = PROVIDERS.include?(provider_name) && provider_uid.present? &&
          verified_email.present? && verified_email.match?(URI::MailTo::EMAIL_REGEXP) && verified

        new(
          kind: :provider,
          provider_name: provider_name,
          provider_uid: provider_uid,
          verified_email: verified_email,
          valid: valid
        )
      end

      private

      def github_email_verified?(auth_hash, info_email)
        return false unless info_email

        extra = value(auth_hash, "extra") || {}
        all_emails = value(extra, "all_emails")
        return false unless all_emails.is_a?(Array)

        all_emails.any? do |candidate|
          value(candidate, "primary") == true && value(candidate, "verified") == true &&
            normalized_email(value(candidate, "email")) == info_email
        end
      end

      def normalized_email(value)
        value.to_s.strip.downcase.presence
      end

      def value(hash, key)
        return unless hash.respond_to?(:[])

        if hash.respond_to?(:key?)
          return hash[key] if hash.key?(key)
          return hash[key.to_sym] if hash.key?(key.to_sym)
        end

        hash[key] || hash[key.to_sym]
      end
    end

    attr_reader :kind, :user_id, :provider_name, :provider_uid, :verified_email

    def initialize(
      kind:,
      valid:,
      user_id: nil,
      password: nil,
      password_confirmation: nil,
      provider_name: nil,
      provider_uid: nil,
      verified_email: nil
    )
      raise ArgumentError, "unsupported invitation identity proof" unless KINDS.include?(kind)

      @kind = kind
      @valid = valid == true
      @user_id = user_id
      @password = frozen_copy(password)
      @password_confirmation = frozen_copy(password_confirmation)
      @provider_name = frozen_copy(provider_name)
      @provider_uid = frozen_copy(provider_uid)
      @verified_email = frozen_copy(verified_email)
      freeze
    end

    KINDS.each do |proof_kind|
      define_method("#{proof_kind}?") { kind == proof_kind }
    end

    def valid?
      @valid
    end

    def password
      @password&.dup
    end

    def password_confirmation
      @password_confirmation&.dup
    end

    def inspect
      "#<#{self.class.name} kind=#{kind.inspect} [FILTERED]>"
    end

    alias_method :to_s, :inspect

    def as_json(*)
      "[FILTERED]"
    end

    private

    def frozen_copy(value)
      value&.dup&.freeze
    end
  end
end
