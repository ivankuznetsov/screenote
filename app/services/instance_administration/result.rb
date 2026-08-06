# frozen_string_literal: true

module InstanceAdministration
  class Result
    attr_reader :status, :user, :token, :presentation, :expires_at, :errors, :details

    def initialize(
      status:,
      user: nil,
      token: nil,
      presentation: nil,
      expires_at: nil,
      errors: {},
      details: {}
    )
      @status = status.to_sym
      @user = user
      @token = token
      @presentation = presentation
      @expires_at = expires_at
      @errors = normalized_errors(errors)
      @details = details.to_h.freeze
      freeze
    end

    def success?
      %i[issued recovered restored revoked suspended transferred].include?(status)
    end

    def inspect
      "#<#{self.class.name} status=#{status.inspect} user_id=#{user&.id.inspect} " \
        "token_id=#{token&.id.inspect} [FILTERED]>"
    end

    alias_method :to_s, :inspect

    def as_json(*)
      {
        "status" => status.to_s,
        "user_id" => user&.id,
        "token_id" => token&.id,
        "expires_at" => expires_at,
        "error_attributes" => errors.keys.map(&:to_s),
        "details" => details
      }
    end

    private

    def normalized_errors(errors)
      errors.to_h.each_with_object({}) do |(attribute, messages), result|
        result[attribute.to_sym] = Array(messages).map(&:to_s).freeze
      end.freeze
    end
  end
end
