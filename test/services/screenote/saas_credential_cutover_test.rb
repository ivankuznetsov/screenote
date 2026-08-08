# frozen_string_literal: true

require "test_helper"

module Screenote
  class SaasCredentialCutoverTest < ActiveSupport::TestCase
    class AppliedConnection
      def quote(value)
        "'#{value}'"
      end

      def quote_table_name(value)
        value.to_s
      end

      def quote_column_name(value)
        value.to_s
      end

      def select_value(sql)
        "0"
      end
    end

    class DigestBatch
      def initialize(values)
        @values = values
      end

      def pluck(*) = @values
    end

    class DigestModel
      attr_reader :batch_size, :table_name

      def initialize(table_name, batches)
        @table_name = table_name
        @batches = batches
      end

      def unscoped = self

      def in_batches(of:)
        @batch_size = of
        @batches.each { |values| yield DigestBatch.new(values) }
      end
    end

    class RecordingMigrationContext
      attr_reader :migrate_calls

      def initialize(remains_pending: false, applied_versions: [ SaasCredentialCutover::MIGRATION_VERSION.to_i ])
        @remains_pending = remains_pending
        @applied_versions = applied_versions
        @migrate_calls = 0
      end

      def get_all_versions
        @applied_versions
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

    test "idempotent resume applies every later migration before booting the successor" do
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

      assert_equal 1, migration_context.migrate_calls,
        "resume must apply migrations after the credential rewrite before booting the successor"
    end

    test "stored credentials are validated in bounded table batches" do
      model = DigestModel.new("oauth_access_tokens", [
        [ [ "a" * 64, nil, "" ] ],
        [ [ "b" * 64, "c" * 64, "d" * 64 ] ]
      ])
      columns = [
        [ :token, false, false ],
        [ :refresh_token, true, false ],
        [ :previous_refresh_token, false, true ]
      ]
      operation = SaasCredentialCutover.new(
        deployment: Struct.new(:saas?).new(true),
        connection: AppliedConnection.new,
        migration_context: RecordingMigrationContext.new,
        digest_models: [ [ model, columns ] ]
      )

      operation.send(:verify_migrated_storage!)

      assert_equal SaasCredentialCutover::DIGEST_BATCH_SIZE, model.batch_size
    end

    test "idempotent resume fails closed when a stored credential is malformed" do
      model = DigestModel.new("oauth_access_tokens", [ [ [ "malformed" ] ] ])
      operation = SaasCredentialCutover.new(
        deployment: Struct.new(:saas?).new(true),
        connection: AppliedConnection.new,
        migration_context: RecordingMigrationContext.new,
        digest_models: [ [ model, [ [ :token, false, false ] ] ] ]
      )

      error = assert_raises(SaasCredentialCutover::Error) do
        operation.send(:verify_migrated_storage!)
      end
      assert_includes error.message, "invalid oauth_access_tokens.token rows"
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
