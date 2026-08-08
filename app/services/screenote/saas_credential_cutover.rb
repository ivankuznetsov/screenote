# frozen_string_literal: true

module Screenote
  class SaasCredentialCutover
    MIGRATION_VERSION = "20260805131000"
    AUTHORIZATION = "authorized"
    DIGEST_BATCH_SIZE = 1_000
    LEGACY_WITNESS_QUERIES = {
      access_grant: <<~SQL.squish,
        SELECT id, token
        FROM oauth_access_grants
        WHERE token IS NOT NULL
        ORDER BY id
        LIMIT 1
      SQL
      access_token: <<~SQL.squish,
        SELECT id, token
        FROM oauth_access_tokens
        WHERE token IS NOT NULL
        ORDER BY id
        LIMIT 1
      SQL
      refresh_token: <<~SQL.squish,
        SELECT id, refresh_token
        FROM oauth_access_tokens
        WHERE refresh_token IS NOT NULL AND refresh_token <> ''
        ORDER BY id
        LIMIT 1
      SQL
      application: <<~SQL.squish
        SELECT id, uid, secret
        FROM oauth_applications
        WHERE secret IS NOT NULL AND secret <> ''
        ORDER BY id
        LIMIT 1
      SQL
    }.freeze

    class Error < StandardError; end

    Result = Data.define(:status, :witness_count) do
      def inspect
        "#<#{self.class.name} status=#{status.inspect} witness_count=#{witness_count}>"
      end

      alias_method :to_s, :inspect

      def as_json(*)
        { "status" => status.to_s, "witness_count" => witness_count }
      end
    end

    class Witness
      attr_reader :id, :kind, :lookup, :secondary_lookup

      def initialize(kind:, id:, lookup:, secondary_lookup:)
        @kind = kind
        @id = id
        @lookup = lookup
        @secondary_lookup = secondary_lookup
        freeze
      end

      def inspect
        "#<#{self.class.name} kind=#{kind.inspect} id=#{id.inspect} [FILTERED]>"
      end

      alias_method :to_s, :inspect

      def as_json(*)
        { "kind" => kind.to_s, "id" => id }
      end
    end

    def self.call
      new.call
    end

    def initialize(
      deployment: Screenote::Deployment.current,
      connection: ActiveRecord::Base.connection,
      migration_context: ActiveRecord::Base.connection_pool.migration_context,
      digest_models: nil
    )
      @deployment = deployment
      @connection = connection
      @migration_context = migration_context
      @digest_models = digest_models
    end

    # This process must be started only by bin/saas-credential-cutover after
    # Kamal has placed the proxy in maintenance and proved every app process is
    # stopped. Raw legacy values live only in these local variables so the new
    # digest-only runtime can be checked immediately after migration.
    def call
      validate_runtime!

      credential_migration_was_applied = migration_applied?
      witnesses = credential_migration_was_applied ? [] : capture_legacy_witnesses
      migration_context.migrate
      reset_oauth_models!
      verify_migration_applied!
      verify_all_migrations_applied!
      verify_migrated_storage!
      verify_runtime_lookups!(witnesses)

      Result.new(
        status: credential_migration_was_applied ? :already_applied : :migrated,
        witness_count: witnesses.size
      )
    rescue Error
      raise
    rescue ActiveRecord::MigrationError => error
      raise Error, "credential migration preflight failed: #{error.message}"
    rescue StandardError => error
      raise Error, "credential cutover failed safely (#{error.class})"
    end

    private

    attr_reader :connection, :deployment, :migration_context

    def validate_runtime!
      unless ENV["SCREENOTE_SAAS_CREDENTIAL_CUTOVER"] == AUTHORIZATION
        raise Error, "credential cutover requires the dedicated operator command"
      end
      raise Error, "credential cutover is available only in SaaS mode" unless deployment.saas?
    end

    def migration_applied?
      migration_context.get_all_versions.include?(MIGRATION_VERSION.to_i)
    end

    def verify_migration_applied!
      raise Error, "credential migration did not complete" unless migration_applied?
    end

    def verify_all_migrations_applied!
      raise Error, "credential cutover left later migrations pending" if migration_context.needs_migration?
    end

    def capture_legacy_witnesses
      [
        access_grant_witness,
        access_token_witness,
        refresh_token_witness,
        application_witness
      ].compact.freeze
    end

    def access_grant_witness
      row = first_row(:access_grant)
      witness(:access_grant, row, :token)
    end

    def access_token_witness
      row = first_row(:access_token)
      witness(:access_token, row, :token)
    end

    def refresh_token_witness
      row = first_row(:refresh_token)
      witness(:refresh_token, row, :refresh_token)
    end

    def application_witness
      row = first_row(:application)
      return unless row

      Witness.new(
        kind: :application,
        id: row.fetch("id").to_i,
        lookup: row.fetch("uid").dup.freeze,
        secondary_lookup: row.fetch("secret").dup.freeze
      )
    end

    def witness(kind, row, column)
      return unless row

      Witness.new(
        kind:,
        id: row.fetch("id").to_i,
        lookup: row.fetch(column.to_s).dup.freeze,
        secondary_lookup: nil
      )
    end

    def first_row(kind)
      connection.select_one(LEGACY_WITNESS_QUERIES.fetch(kind))
    end

    def reset_oauth_models!
      oauth_models.each(&:reset_column_information)
    end

    def oauth_models
      [ Doorkeeper::AccessGrant, Doorkeeper::AccessToken, Doorkeeper::Application ]
    end

    def verify_migrated_storage!
      digest_models.each do |model, columns|
        names = columns.map(&:first)

        model.unscoped.in_batches(of: DIGEST_BATCH_SIZE) do |batch|
          batch.pluck(*names).each do |values|
            values = [ values ] if names.one?

            columns.zip(values).each do |(column, nullable, blankable), value|
              next if valid_digest_storage?(value, nullable:, blankable:)

              raise Error, "credential cutover left invalid #{model.table_name}.#{column} rows"
            end
          end
        end
      end
    end

    def digest_models
      @digest_models || [
        [ Doorkeeper::AccessGrant, [ [ :token, false, false ] ] ],
        [ Doorkeeper::AccessToken, [
          [ :token, false, false ],
          [ :refresh_token, true, false ],
          [ :previous_refresh_token, false, true ]
        ] ],
        [ Doorkeeper::Application, [ [ :secret, true, false ] ] ]
      ]
    end

    def valid_digest_storage?(value, nullable:, blankable:)
      (nullable && value.nil?) ||
        (blankable && value == "") ||
        value.to_s.match?(/\A[0-9a-f]{64}\z/)
    end

    def verify_runtime_lookups!(witnesses)
      witnesses.each do |entry|
        record =
          case entry.kind
          when :access_grant
            Doorkeeper::AccessGrant.by_token(entry.lookup)
          when :access_token
            Doorkeeper::AccessToken.by_token(entry.lookup)
          when :refresh_token
            Doorkeeper::AccessToken.by_refresh_token(entry.lookup)
          when :application
            Doorkeeper::Application.by_uid_and_secret(entry.lookup, entry.secondary_lookup)
          end

        unless record&.id == entry.id
          raise Error, "credential cutover runtime verification failed for #{entry.kind}"
        end
      end
    end
  end
end
