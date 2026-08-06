# frozen_string_literal: true

require "test_helper"
require Rails.root.join("db/migrate/20260805134000_add_account_recovery_provenance_to_authentication_tokens").to_s

class AddAccountRecoveryProvenanceTest < ActiveSupport::TestCase
  self.fixture_table_names = []
  self.use_transactional_tests = false

  class MigrationDatabaseRecord < ActiveRecord::Base
    self.abstract_class = true
  end

  setup do
    @database_class = MigrationDatabaseRecord
    @database_class.establish_connection(migration_database_config)
    @connection = @database_class.connection
    drop_schema
    create_legacy_schema
  end

  def after_teardown
    drop_schema if @connection
    super
  ensure
    @database_class&.remove_connection
  end

  test "adds exact issuer provenance constraints and index" do
    run_migration

    assert_includes @connection.columns(:authentication_tokens).map(&:name), "issued_by_user_id"
    assert_includes @connection.indexes(:authentication_tokens).map(&:name),
      "index_auth_tokens_on_recovery_issuer_state"
    assert_includes @connection.check_constraints(:authentication_tokens).map(&:name),
      "authentication_tokens_recovery_issuer"
    assert @connection.foreign_keys(:authentication_tokens).any? do |foreign_key|
      foreign_key.to_table == "users" && foreign_key.options[:column].to_s == "issued_by_user_id"
    end

    insert_token(id: 10, purpose: 4, issued_by_user_id: 1)
    insert_token(id: 11, purpose: 1, issued_by_user_id: nil)
    assert_statement_invalid { insert_token(id: 12, purpose: 4, issued_by_user_id: nil) }
    assert_statement_invalid { insert_token(id: 13, purpose: 1, issued_by_user_id: 1) }
  end

  test "preflight reports all recovery rows before changing the schema" do
    insert_token(id: 7, purpose: 4)
    insert_token(id: 9, purpose: 4)

    error = assert_raises(ActiveRecord::MigrationError) { run_migration }

    assert_match(/authentication token IDs.*7, 9/i, error.message)
    assert_not_includes @connection.columns(:authentication_tokens).map(&:name), "issued_by_user_id"
  end

  test "is irreversible because recovery provenance cannot be discarded" do
    assert_raises(ActiveRecord::IrreversibleMigration) do
      capture_io do
        AddAccountRecoveryProvenanceToAuthenticationTokens.new.exec_migration(@connection, :down)
      end
    end
  end

  private

  def create_legacy_schema
    @connection.create_table(:users) { |table| table.string :email, null: false }
    @connection.create_table :authentication_tokens do |table|
      table.references :user, null: false
      table.integer :purpose, null: false
      table.integer :state, null: false, default: 0
      table.timestamps null: false
    end
    @connection.add_foreign_key :authentication_tokens, :users
    insert(:users, id: 1, email: "administrator@example.test")
  end

  def insert_token(id:, purpose:, issued_by_user_id: :absent)
    attributes = {
      id: id,
      user_id: 1,
      purpose: purpose,
      state: 0,
      created_at: Time.current,
      updated_at: Time.current
    }
    attributes[:issued_by_user_id] = issued_by_user_id unless issued_by_user_id == :absent
    insert(:authentication_tokens, **attributes)
  end

  def insert(table, **attributes)
    columns = attributes.keys.map { |column| @connection.quote_column_name(column) }.join(", ")
    values = attributes.values.map { |value| @connection.quote(value) }.join(", ")
    @connection.execute(<<~SQL.squish)
      INSERT INTO #{@connection.quote_table_name(table)} (#{columns}) VALUES (#{values})
    SQL
  end

  def assert_statement_invalid(&block)
    assert_raises(ActiveRecord::StatementInvalid) do
      @connection.transaction(requires_new: true, &block)
    end
  end

  def run_migration
    capture_io do
      @connection.transaction do
        AddAccountRecoveryProvenanceToAuthenticationTokens.new.exec_migration(@connection, :up)
      end
    end
  end

  def drop_schema
    %i[authentication_tokens users].each do |table|
      @connection.drop_table(table, if_exists: true, force: :cascade)
    end
  end

  def migration_database_config
    ENV["MIGRATION_TEST_DATABASE_URL"].presence || { adapter: "sqlite3", database: ":memory:" }
  end
end
