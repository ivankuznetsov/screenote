# frozen_string_literal: true

require "test_helper"
require Rails.root.join("db/migrate/20260805131000_harden_oauth_principals_and_token_secrets").to_s

class HardenOauthPrincipalsAndTokenSecretsTest < ActiveSupport::TestCase
  self.fixture_table_names = []
  self.use_transactional_tests = false

  class MigrationDatabaseRecord < ActiveRecord::Base
    self.abstract_class = true
  end

  setup do
    @database_class = MigrationDatabaseRecord
    @database_class.establish_connection(migration_database_config)
    @connection = @database_class.connection
    drop_legacy_schema
  end

  def after_teardown
    drop_legacy_schema if @connection
    super
  ensure
    @database_class&.remove_connection
  end

  test "backfills explicit principals and irreversibly hashes every reusable OAuth secret" do
    create_legacy_schema
    insert_legacy_graph

    run_migration

    user_grant = row(:oauth_access_grants, 20)
    project_token = row(:oauth_access_tokens, 30)
    application = row(:oauth_applications, 10)
    device_grant = row(:oauth_device_grants, 40)

    assert_equal "user", user_grant.fetch("principal_kind")
    assert_equal "project", project_token.fetch("principal_kind")
    assert_equal "user", device_grant.fetch("principal_kind")
    assert_equal Digest::SHA256.hexdigest("authorization-code-sentinel"), user_grant.fetch("token")
    assert_equal Digest::SHA256.hexdigest("access-token-sentinel"), project_token.fetch("token")
    assert_equal Digest::SHA256.hexdigest("refresh-token-sentinel"), project_token.fetch("refresh_token")
    assert_equal Digest::SHA256.hexdigest("previous-refresh-sentinel"), project_token.fetch("previous_refresh_token")
    assert_equal Digest::SHA256.hexdigest("application-secret-sentinel"), application.fetch("secret")
    assert_equal 64, application.fetch("registration_fingerprint").length

    assert_constraint :oauth_access_grants, "oauth_access_grants_valid_principal"
    assert_constraint :oauth_access_tokens, "oauth_access_tokens_valid_principal"
    assert_constraint :oauth_device_grants, "oauth_device_grants_valid_principal"
    assert_constraint :oauth_access_tokens, "oauth_access_tokens_hashed_refresh_token"
    assert_project_cascade :oauth_access_grants
    assert_project_cascade :oauth_access_tokens
    assert_project_cascade :oauth_device_grants

    @connection.execute("DELETE FROM projects WHERE id = 2")
    assert_nil row(:oauth_access_tokens, 30, required: false)
  end

  test "database constraints reject widened or plaintext principals" do
    create_legacy_schema
    insert_legacy_graph
    run_migration

    assert_statement_invalid do
      insert(:oauth_access_tokens,
        id: 31, application_id: 10, resource_owner_id: 1,
        token: Digest::SHA256.hexdigest("invalid-user-project"), scopes: "mcp_read",
        principal_kind: "user", project_id: 2, created_at: Time.current)
    end
    assert_statement_invalid do
      insert(:oauth_access_tokens,
        id: 32, application_id: 10, resource_owner_id: 1,
        token: "plaintext", scopes: "mcp_read",
        principal_kind: "project", project_id: 2, created_at: Time.current)
    end
    assert_statement_invalid do
      insert(:oauth_access_tokens,
        id: 33, application_id: 10, resource_owner_id: nil,
        token: Digest::SHA256.hexdigest("missing-owner"), scopes: "mcp_read",
        principal_kind: "user", project_id: nil, created_at: Time.current)
    end
  end

  test "preflight reports invalid legacy authority rows without mutation" do
    create_legacy_schema
    insert_legacy_graph
    insert(:oauth_access_tokens,
      id: 31, application_id: 10, resource_owner_id: nil,
      token: "orphan-token-sentinel", scopes: "mcp_read", created_at: Time.current)
    insert(:oauth_device_grants,
      id: 41, application_id: 10, resource_owner_id: nil,
      device_code: "invalid-device", user_code: "WRONG-CODE", scopes: "mcp_read",
      expires_at: 10.minutes.from_now, polling_interval: 5,
      approved_at: Time.current, created_at: Time.current, updated_at: Time.current)

    error = assert_raises(ActiveRecord::MigrationError) { run_migration }

    assert_match(/missing resource owner IDs: 31/, error.message)
    assert_match(/device_grants with invalid approval state: 41/, error.message)
    assert_not @connection.column_exists?(:oauth_access_tokens, :principal_kind)
    assert_equal "access-token-sentinel", row(:oauth_access_tokens, 30).fetch("token")
  end

  test "preserves duplicate legacy dynamic clients and chooses the oldest as canonical" do
    create_legacy_schema
    insert_legacy_graph
    insert(:oauth_applications,
      id: 11, name: "Screenote CLI", uid: "duplicate-client", secret: nil,
      redirect_uri: "http://127.0.0.1:4321/callback", scopes: "mcp_read",
      confidential: false, dynamic: true, created_at: 1.minute.from_now, updated_at: Time.current)

    run_migration

    canonical = row(:oauth_applications, 10)
    duplicate = row(:oauth_applications, 11)
    assert_equal 64, canonical.fetch("registration_fingerprint").length
    assert_nil duplicate.fetch("registration_fingerprint")
    assert_equal 2, @connection.select_value("SELECT COUNT(*) FROM oauth_applications").to_i
    assert_includes @connection.indexes(:oauth_applications).map(&:name),
      "index_dynamic_oauth_apps_on_registration_fingerprint"
  end

  test "migration is irreversible" do
    assert_raises(ActiveRecord::IrreversibleMigration) do
      capture_io { HardenOauthPrincipalsAndTokenSecrets.new.exec_migration(@connection, :down) }
    end
  end

  private

  def create_legacy_schema
    @connection.create_table(:users) { |table| table.string :email }
    @connection.create_table(:projects) { |table| table.references :user, null: false }
    @connection.create_table :oauth_applications do |table|
      table.string :name, null: false
      table.string :uid, null: false
      table.string :secret
      table.text :redirect_uri, null: false
      table.string :scopes, null: false, default: ""
      table.boolean :confidential, null: false, default: false
      table.boolean :dynamic, null: false, default: false
      table.timestamps null: false
    end
    @connection.create_table :oauth_access_grants do |table|
      table.references :resource_owner, null: false
      table.references :application, null: false
      table.string :token, null: false
      table.integer :expires_in, null: false
      table.text :redirect_uri, null: false
      table.string :scopes, null: false, default: ""
      table.integer :project_id
      table.string :code_challenge
      table.string :code_challenge_method
      table.datetime :created_at, null: false
      table.datetime :revoked_at
    end
    @connection.create_table :oauth_access_tokens do |table|
      table.references :resource_owner
      table.references :application, null: false
      table.string :token, null: false
      table.string :refresh_token
      table.string :previous_refresh_token, null: false, default: ""
      table.integer :expires_in
      table.string :scopes
      table.integer :project_id
      table.datetime :created_at, null: false
      table.datetime :revoked_at
    end
    @connection.create_table :oauth_device_grants do |table|
      table.references :application, null: false
      table.references :resource_owner
      table.string :device_code, null: false
      table.string :user_code, null: false
      table.string :scopes, null: false
      table.datetime :expires_at, null: false
      table.integer :polling_interval, null: false, default: 5
      table.datetime :last_polled_at
      table.datetime :approved_at
      table.datetime :denied_at
      table.timestamps null: false
    end

    @connection.add_foreign_key :projects, :users
    @connection.add_foreign_key :oauth_access_grants, :oauth_applications, column: :application_id, on_delete: :cascade
    @connection.add_foreign_key :oauth_access_grants, :projects, column: :project_id, on_delete: :nullify
    @connection.add_foreign_key :oauth_access_grants, :users, column: :resource_owner_id, on_delete: :cascade
    @connection.add_foreign_key :oauth_access_tokens, :oauth_applications, column: :application_id, on_delete: :cascade
    @connection.add_foreign_key :oauth_access_tokens, :projects, column: :project_id, on_delete: :nullify
    @connection.add_foreign_key :oauth_access_tokens, :users, column: :resource_owner_id, on_delete: :cascade
    @connection.add_foreign_key :oauth_device_grants, :oauth_applications, column: :application_id, on_delete: :cascade
    @connection.add_foreign_key :oauth_device_grants, :users, column: :resource_owner_id, on_delete: :cascade
  end

  def insert_legacy_graph
    insert(:users, id: 1, email: "reviewer@example.test")
    insert(:projects, id: 2, user_id: 1)
    insert(:oauth_applications,
      id: 10, name: "Screenote CLI", uid: "client-id", secret: "application-secret-sentinel",
      redirect_uri: "http://127.0.0.1:4321/callback", scopes: "mcp_read",
      confidential: false, dynamic: true, created_at: Time.current, updated_at: Time.current)
    insert(:oauth_access_grants,
      id: 20, application_id: 10, resource_owner_id: 1,
      token: "authorization-code-sentinel", expires_in: 600,
      redirect_uri: "http://127.0.0.1:4321/callback", scopes: "mcp_read",
      project_id: nil, created_at: Time.current)
    insert(:oauth_access_tokens,
      id: 30, application_id: 10, resource_owner_id: 1,
      token: "access-token-sentinel", refresh_token: "refresh-token-sentinel",
      previous_refresh_token: "previous-refresh-sentinel", expires_in: 3600,
      scopes: "mcp_read", project_id: 2, created_at: Time.current)
    insert(:oauth_device_grants,
      id: 40, application_id: 10, resource_owner_id: 1,
      device_code: "approved-device-sentinel", user_code: "READY-CODE", scopes: "mcp_read",
      expires_at: 10.minutes.from_now, polling_interval: 5,
      approved_at: Time.current, created_at: Time.current, updated_at: Time.current)
  end

  def row(table, id, required: true)
    record = @connection.select_one(<<~SQL.squish)
      SELECT * FROM #{@connection.quote_table_name(table)} WHERE id = #{@connection.quote(id)}
    SQL
    assert record, "Expected #{table} row #{id}" if required
    record
  end

  def insert(table, **attributes)
    columns = attributes.keys.map { |column| @connection.quote_column_name(column) }.join(", ")
    values = attributes.values.map { |value| @connection.quote(value) }.join(", ")
    @connection.execute(<<~SQL.squish)
      INSERT INTO #{@connection.quote_table_name(table)} (#{columns}) VALUES (#{values})
    SQL
  end

  def assert_constraint(table, name)
    assert_includes @connection.check_constraints(table).map(&:name), name
  end

  def assert_project_cascade(table)
    foreign_key = @connection.foreign_keys(table).find do |candidate|
      candidate.to_table == "projects" && candidate.options.fetch(:column).to_s == "project_id"
    end
    assert foreign_key
    assert_equal :cascade, foreign_key.on_delete
  end

  def assert_statement_invalid(&block)
    assert_raises(ActiveRecord::StatementInvalid) do
      @connection.transaction(requires_new: true, &block)
    end
  end

  def run_migration
    capture_io do
      @connection.transaction do
        HardenOauthPrincipalsAndTokenSecrets.new.exec_migration(@connection, :up)
      end
    end
  end

  def drop_legacy_schema
    %i[oauth_device_grants oauth_access_tokens oauth_access_grants oauth_applications projects users].each do |table|
      @connection.drop_table(table, if_exists: true)
    end
  end

  def migration_database_config
    ENV["MIGRATION_TEST_DATABASE_URL"].presence || { adapter: "sqlite3", database: ":memory:" }
  end
end
