# frozen_string_literal: true

module InstanceAccounts
  class List
    Account = Data.define(:id, :email, :access_status, :administrator, :created_at) do
      def active?
        access_status == "active"
      end

      def suspended?
        access_status == "suspended"
      end
    end

    Result = Data.define(:status, :accounts, :administrator_id) do
      def success?
        status == :listed
      end
    end

    class << self
      def call(actor:, channel: "web")
        new(actor: actor, channel: channel).call
      end
    end

    def initialize(actor:, channel: "web")
      @actor = actor
      @channel = channel
    end

    def call
      DatabaseRetry.call do
        Installation.transaction do
          locked = InstanceAdministration::Authority.lock(actor: actor)
          next result(:unavailable) unless InstanceAdministration::Authority.available?(locked)
          unless InstanceAdministration::Authority.authorized?(locked)
            InstanceAdministration::Audit.denied!(
              installation: locked.installation,
              actor: locked.actor,
              target: nil,
              action: :list_accounts,
              reason: :forbidden,
              channel: channel
            )
            next result(:forbidden)
          end

          accounts = User.order(:email, :id)
            .pluck(:id, :email, :access_status, :created_at)
            .map do |id, email, access_status, created_at|
              canonical_access_status = User.access_statuses.key(access_status) || access_status.to_s
              Account.new(
                id: id,
                email: email,
                access_status: canonical_access_status,
                administrator: id == locked.administrator.id,
                created_at: created_at
              )
            end
            .freeze
          result(:listed, accounts: accounts, administrator_id: locked.administrator.id)
        end
      end
    rescue DatabaseRetry::Exhausted
      result(:retryable_busy)
    rescue ActiveRecord::ActiveRecordError
      result(:unavailable)
    end

    private

    attr_reader :actor, :channel

    def result(status, accounts: [], administrator_id: nil)
      Result.new(status: status, accounts: accounts.freeze, administrator_id: administrator_id)
    end
  end
end
