# frozen_string_literal: true

require "test_helper"
require Rails.root.join("db/migrate/20260712153000_repair_legacy_api_key_token_storage").to_s

class RepairLegacyApiKeyTokenStorageTest < ActiveSupport::TestCase
  self.fixture_table_names = []
  self.use_transactional_tests = false

  class MigrationDatabaseRecord < ActiveRecord::Base
    self.abstract_class = true
  end

  setup do
    @database_class = MigrationDatabaseRecord
    @database_class.establish_connection(migration_database_config)
    @connection = @database_class.connection
    @connection.drop_table(:api_keys, if_exists: true)
  end

  def after_teardown
    @connection.drop_table(:api_keys, if_exists: true) if @connection
    super
  ensure
    @database_class&.remove_connection
  end

  test "converts legacy plaintext tokens without invalidating existing API keys" do
    create_legacy_schema
    raw_token = "sk_proj_#{"a" * 48}"
    insert_legacy_key(raw_token)

    2.times { run_migration }

    columns = @connection.columns(:api_keys).index_by(&:name)
    assert_not columns.key?("token")
    assert_equal false, columns.fetch("token_digest").null
    assert columns.key?("token_prefix")
    assert @connection.index_exists?(:api_keys, :token_digest, unique: true)

    migrated = @connection.select_one("SELECT token_digest, token_prefix FROM api_keys")
    assert_equal Digest::SHA256.hexdigest(raw_token), migrated.fetch("token_digest")
    assert_equal raw_token.first(12), migrated.fetch("token_prefix")
  end

  test "is a no-op when the original create migration already made the secure schema" do
    create_secure_schema
    digest = Digest::SHA256.hexdigest("already-secure")
    @connection.execute(<<~SQL.squish)
      INSERT INTO api_keys (token_digest, token_prefix, name)
      VALUES (#{@connection.quote(digest)}, 'sk_proj_safe', 'Existing key')
    SQL

    2.times { run_migration }

    assert_equal %w[id name token_digest token_prefix], @connection.columns(:api_keys).map(&:name).sort
    assert_equal digest, @connection.select_value("SELECT token_digest FROM api_keys")
    assert @connection.index_exists?(:api_keys, :token_digest, unique: true)
  end

  test "fails closed for an unknown API key schema" do
    @connection.create_table(:api_keys) { |table| table.string :name, null: false }

    error = assert_raises(ActiveRecord::MigrationError) { run_migration }

    assert_match(/unsupported api_keys schema/i, error.message)
  end

  test "is irreversible because plaintext tokens cannot be reconstructed" do
    assert_raises(ActiveRecord::IrreversibleMigration) do
      capture_io { RepairLegacyApiKeyTokenStorage.new.exec_migration(@connection, :down) }
    end
  end

  test "runs the PostgreSQL table lock transactionally" do
    skip unless @connection.adapter_name == "PostgreSQL"

    create_legacy_schema
    run_migration

    assert_not @connection.column_exists?(:api_keys, :token)
  end

  private

  def create_legacy_schema
    @connection.create_table :api_keys do |table|
      table.string :token, null: false
      table.string :name, null: false
    end
    @connection.add_index :api_keys, :token, unique: true
  end

  def create_secure_schema
    @connection.create_table :api_keys do |table|
      table.string :token_digest, null: false
      table.string :token_prefix
      table.string :name, null: false
    end
    @connection.add_index :api_keys, :token_digest, unique: true
  end

  def insert_legacy_key(token)
    @connection.execute(<<~SQL.squish)
      INSERT INTO api_keys (token, name)
      VALUES (#{@connection.quote(token)}, 'Legacy key')
    SQL
  end

  def run_migration
    capture_io do
      @connection.transaction do
        RepairLegacyApiKeyTokenStorage.new.exec_migration(@connection, :up)
      end
    end
  end

  def migration_database_config
    ENV["MIGRATION_TEST_DATABASE_URL"].presence || { adapter: "sqlite3", database: ":memory:" }
  end
end
