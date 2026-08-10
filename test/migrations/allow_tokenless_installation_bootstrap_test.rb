# frozen_string_literal: true

require "test_helper"
require Rails.root.join("db/migrate/20260809120000_allow_tokenless_installation_bootstrap").to_s

class AllowTokenlessInstallationBootstrapTest < ActiveSupport::TestCase
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

  test "allows tokenless bootstrap while preserving every legacy installation state" do
    insert_installation(
      id: 1,
      singleton_key: "legacy-unclaimed",
      state: "unclaimed",
      bootstrap_token_digest: "a" * 64
    )
    insert_installation(
      id: 2,
      singleton_key: "claimed",
      state: "claimed",
      administrator_id: 7,
      claimed_at: Time.current
    )
    insert_installation(
      id: 3,
      singleton_key: "saas",
      deployment_mode: "saas",
      state: "saas",
      storage_service: "rabata"
    )

    run_migration(:up)

    assert @connection.column_exists?(:installations, :bootstrap_token_digest)
    assert_equal [ "a" * 64, nil, nil ], values(:installations, :bootstrap_token_digest)
    assert_equal %w[installations_bootstrap_digest installations_valid_state],
      @connection.check_constraints(:installations).map(&:name).grep(/installations_(?:valid_state|bootstrap_digest)/).sort

    insert_installation(id: 4, singleton_key: "fresh", state: "unclaimed")
    assert_invalid_installation(id: 5, singleton_key: "claimed-without-actor", state: "claimed")
    assert_invalid_installation(
      id: 6,
      singleton_key: "unclaimed-with-actor",
      state: "unclaimed",
      administrator_id: 7
    )
    assert_invalid_installation(
      id: 7,
      singleton_key: "saas-with-actor",
      deployment_mode: "saas",
      state: "saas",
      storage_service: "rabata",
      administrator_id: 7
    )
    assert_invalid_installation(
      id: 8,
      singleton_key: "claimed-with-token",
      state: "claimed",
      administrator_id: 7,
      claimed_at: Time.current,
      bootstrap_token_digest: "b" * 64
    )
    assert_invalid_installation(
      id: 9,
      singleton_key: "malformed-transition-token",
      state: "unclaimed",
      bootstrap_token_digest: "short"
    )
  end

  test "restores the legacy constraint while no tokenless installation exists" do
    insert_installation(
      id: 1,
      singleton_key: "legacy-unclaimed",
      state: "unclaimed",
      bootstrap_token_digest: "a" * 64
    )

    run_migration(:up)
    run_migration(:down)

    assert_invalid_installation(id: 2, singleton_key: "tokenless", state: "unclaimed")
  end

  test "refuses rollback after a tokenless installation is prepared" do
    run_migration(:up)
    insert_installation(id: 1, singleton_key: "tokenless", state: "unclaimed")

    assert_raises(ActiveRecord::IrreversibleMigration) do
      run_migration(:down)
    end
  end

  private

  def create_legacy_schema
    @connection.create_table(:users) { |table| table.string :email, null: false }
    @connection.create_table :installations do |table|
      table.string :singleton_key, null: false
      table.string :deployment_mode, null: false
      table.string :state, null: false
      table.string :storage_service, null: false
      table.string :storage_namespace_fingerprint, limit: 64, null: false
      table.string :bootstrap_token_digest, limit: 64
      table.references :administrator
      table.datetime :claimed_at
      table.timestamps null: false
    end
    @connection.add_foreign_key :installations, :users, column: :administrator_id
    @connection.add_check_constraint :installations,
      "bootstrap_token_digest IS NULL OR length(bootstrap_token_digest) = 64",
      name: "installations_bootstrap_digest"
    @connection.add_check_constraint :installations,
      AllowTokenlessInstallationBootstrap::LEGACY_STATE_CONSTRAINT,
      name: "installations_valid_state"
    insert(:users, id: 7, email: "administrator@example.test")
  end

  def insert_installation(id:, singleton_key:, state:, deployment_mode: "self_hosted",
    storage_service: "self_hosted_local", administrator_id: nil,
    bootstrap_token_digest: nil, claimed_at: nil)
    insert(
      :installations,
      id:,
      singleton_key:,
      deployment_mode:,
      state:,
      storage_service:,
      storage_namespace_fingerprint: "f" * 64,
      bootstrap_token_digest:,
      administrator_id:,
      claimed_at:,
      created_at: Time.current,
      updated_at: Time.current
    )
  end

  def assert_invalid_installation(**attributes)
    assert_raises(ActiveRecord::StatementInvalid) do
      @connection.transaction(requires_new: true) { insert_installation(**attributes) }
    end
  end

  def insert(table, **attributes)
    columns = attributes.keys.map { |column| @connection.quote_column_name(column) }.join(", ")
    quoted_values = attributes.values.map { |value| @connection.quote(value) }.join(", ")
    @connection.execute(<<~SQL.squish)
      INSERT INTO #{@connection.quote_table_name(table)} (#{columns}) VALUES (#{quoted_values})
    SQL
  end

  def values(table, column)
    @connection.select_values(<<~SQL.squish)
      SELECT #{@connection.quote_column_name(column)}
      FROM #{@connection.quote_table_name(table)}
      ORDER BY id
    SQL
  end

  def run_migration(direction)
    capture_io do
      @connection.transaction do
        AllowTokenlessInstallationBootstrap.new.exec_migration(@connection, direction)
      end
    end
  end

  def drop_schema
    %i[installations users].each do |table|
      @connection.drop_table(table, if_exists: true, force: :cascade)
    end
  end

  def migration_database_config
    ENV["MIGRATION_TEST_DATABASE_URL"].presence || { adapter: "sqlite3", database: ":memory:" }
  end
end
