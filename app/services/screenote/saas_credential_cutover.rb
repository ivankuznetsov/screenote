# frozen_string_literal: true

module Screenote
  class SaasCredentialCutover
    MIGRATION_VERSION = "20260805131000"
    AUTHORIZATION = "authorized"
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
      migration_context: ActiveRecord::Base.connection_pool.migration_context
    )
      @deployment = deployment
      @connection = connection
      @migration_context = migration_context
    end

    # This process must be started only by bin/saas-credential-cutover after
    # Kamal has placed the proxy in maintenance and proved every app process is
    # stopped. Raw legacy values live only in these local variables so the new
    # digest-only runtime can be checked immediately after migration.
    def call
      validate_runtime!

      connection.transaction do
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
      end
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
      raise Error, "credential cutover requires PostgreSQL" unless connection.adapter_name == "PostgreSQL"
    end

    def migration_applied?
      return false unless connection.data_source_exists?("schema_migrations")

      connection.select_value(<<~SQL.squish).present?
        SELECT 1
        FROM schema_migrations
        WHERE version = #{connection.quote(MIGRATION_VERSION)}
        LIMIT 1
      SQL
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
      digest_columns.each do |table, column, nullable, blankable|
        quoted_table = connection.quote_table_name(table)
        quoted_column = connection.quote_column_name(column)
        allowed = []
        allowed << "#{quoted_column} IS NULL" if nullable
        allowed << "#{quoted_column} = ''" if blankable
        allowed << "#{quoted_column} ~ '^[0-9a-f]{64}$'"

        invalid_count = connection.select_value(<<~SQL.squish).to_i
          SELECT COUNT(*)
          FROM #{quoted_table}
          WHERE NOT COALESCE((#{allowed.join(' OR ')}), FALSE)
        SQL
        raise Error, "credential cutover left invalid #{table}.#{column} rows" unless invalid_count.zero?
      end
    end

    def digest_columns
      [
        [ :oauth_access_grants, :token, false, false ],
        [ :oauth_access_tokens, :token, false, false ],
        [ :oauth_access_tokens, :refresh_token, true, false ],
        [ :oauth_access_tokens, :previous_refresh_token, false, true ],
        [ :oauth_applications, :secret, true, false ]
      ]
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
