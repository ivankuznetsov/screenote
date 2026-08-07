# frozen_string_literal: true

require "test_helper"

module Screenote
  class SaasCredentialCutoverTest < ActiveSupport::TestCase
    class AppliedConnection
      attr_reader :queries, :transaction_calls

      def initialize(invalid_fragment: nil)
        @invalid_fragment = invalid_fragment
        @queries = []
        @transaction_calls = 0
      end

      def adapter_name
        "PostgreSQL"
      end

      def data_source_exists?(name)
        name == "schema_migrations"
      end

      def quote(value)
        "'#{value}'"
      end

      def quote_table_name(value)
        value.to_s
      end

      def quote_column_name(value)
        value.to_s
      end

      def transaction
        @transaction_calls += 1
        yield
      end

      def select_value(sql)
        @queries << sql
        return "1" if sql.include?("schema_migrations")
        return "1" if @invalid_fragment && sql.include?(@invalid_fragment)

        "0"
      end
    end

    class RecordingMigrationContext
      attr_reader :migrate_calls

      def initialize(remains_pending: false)
        @remains_pending = remains_pending
        @migrate_calls = 0
      end

      def migrate
        @migrate_calls += 1
      end

      def needs_migration?
        @remains_pending
      end
    end

    test "result and legacy witnesses redact reusable credentials" do
      result = SaasCredentialCutover::Result.new(status: :migrated, witness_count: 4)
      witness = SaasCredentialCutover::Witness.new(
        kind: :application,
        id: 42,
        lookup: "client-uid-sentinel",
        secondary_lookup: "client-secret-sentinel"
      )

      assert_equal({ "status" => "migrated", "witness_count" => 4 }, result.as_json)
      assert_not_includes witness.inspect, "client-uid-sentinel"
      assert_not_includes witness.to_s, "client-secret-sentinel"
      assert_equal({ "kind" => "application", "id" => 42 }, witness.as_json)
    end

    test "refuses direct or non-SaaS execution before touching the database" do
      deployment = Struct.new(:saas?).new(false)
      connection = Object.new
      migration_context = Object.new
      operation = SaasCredentialCutover.new(deployment:, connection:, migration_context:)

      error = assert_raises(SaasCredentialCutover::Error) { operation.call }
      assert_includes error.message, "dedicated operator command"

      with_environment("SCREENOTE_SAAS_CREDENTIAL_CUTOVER" => "authorized") do
        error = assert_raises(SaasCredentialCutover::Error) { operation.call }
        assert_includes error.message, "only in SaaS mode"
      end
    end

    test "idempotent resume verifies every migrated credential column" do
      deployment = Struct.new(:saas?).new(true)
      connection = AppliedConnection.new
      migration_context = RecordingMigrationContext.new
      operation = SaasCredentialCutover.new(
        deployment:,
        connection:,
        migration_context:
      )

      with_environment("SCREENOTE_SAAS_CREDENTIAL_CUTOVER" => "authorized") do
        result = operation.call

        assert_equal :already_applied, result.status
        assert_equal 0, result.witness_count
      end

      verification_queries = connection.queries.grep(/SELECT COUNT/)
      assert_equal 5, verification_queries.size
      assert verification_queries.all? { |query| query.include?("NOT COALESCE") }
      assert_equal 1, migration_context.migrate_calls,
        "resume must apply migrations after the credential rewrite before booting the successor"
      assert_equal 1, connection.transaction_calls
    end

    test "idempotent resume fails closed when a stored credential is malformed" do
      deployment = Struct.new(:saas?).new(true)
      connection = AppliedConnection.new(invalid_fragment: "oauth_access_tokens")
      operation = SaasCredentialCutover.new(
        deployment:,
        connection:,
        migration_context: RecordingMigrationContext.new
      )

      with_environment("SCREENOTE_SAAS_CREDENTIAL_CUTOVER" => "authorized") do
        error = assert_raises(SaasCredentialCutover::Error) { operation.call }
        assert_includes error.message, "invalid oauth_access_tokens.token rows"
      end
    end

    test "resume fails closed when later migrations remain pending" do
      deployment = Struct.new(:saas?).new(true)
      operation = SaasCredentialCutover.new(
        deployment:,
        connection: AppliedConnection.new,
        migration_context: RecordingMigrationContext.new(remains_pending: true)
      )

      with_environment("SCREENOTE_SAAS_CREDENTIAL_CUTOVER" => "authorized") do
        error = assert_raises(SaasCredentialCutover::Error) { operation.call }
        assert_includes error.message, "left later migrations pending"
      end
    end

    private

    def with_environment(values)
      previous = values.to_h { |key, _value| [ key, ENV[key] ] }
      values.each { |key, value| ENV[key] = value }
      yield
    ensure
      previous.each { |key, value| value.nil? ? ENV.delete(key) : ENV[key] = value }
    end
  end
end
