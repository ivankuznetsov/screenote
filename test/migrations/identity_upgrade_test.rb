# frozen_string_literal: true

require "test_helper"
require Rails.root.join("db/migrate/20260805132000_harden_user_and_invitation_identity").to_s

class IdentityUpgradeTest < ActiveSupport::TestCase
  self.fixture_table_names = []
  self.use_transactional_tests = false

  class MigrationDatabaseRecord < ActiveRecord::Base
    self.abstract_class = true
  end

  CHILD_TABLES = %i[
    sessions projects project_memberships subscriptions annotations
    annotation_comments api_keys oauth_access_grants oauth_access_tokens
    oauth_device_grants installations
  ].freeze

  setup do
    @database_class = MigrationDatabaseRecord
    @database_class.establish_connection(migration_database_config)
    @connection = @database_class.connection
    drop_schema
  end

  def after_teardown
    drop_schema if @connection
    super
  ensure
    @database_class&.remove_connection
  end

  test "canonicalizes valid identities and preserves the complete user child graph" do
    create_legacy_schema
    insert_valid_graph
    child_ids = CHILD_TABLES.to_h { |table| [ table, ids(table) ] }

    run_migration

    user = row(:users, 1)
    invitation = row(:project_invitations, 21)
    assert_equal "owner@example.test", user.fetch("email")
    assert_equal "github", user.fetch("oauth_provider")
    assert_equal "provider-uid", user.fetch("oauth_uid")
    assert_equal 0, user.fetch("access_status").to_i
    assert_equal "invitee@example.test", invitation.fetch("email")
    assert_equal child_ids, CHILD_TABLES.to_h { |table| [ table, ids(table) ] }
    assert_empty sqlite_foreign_key_violations if sqlite?

    assert_includes index_names(:users), "index_users_on_normalized_email"
    assert_includes index_names(:users), "index_users_on_oauth_identity"
    assert_includes index_names(:project_invitations),
      "index_project_invitations_on_pending_normalized_email"
    assert_constraint :users, "users_normalized_email"
    assert_constraint :users, "users_valid_access_status"
    assert_constraint :users, "users_valid_oauth_identity"
    assert_constraint :project_invitations, "project_invitations_valid_status"
    assert @connection.table_exists?(:installation_audit_events)
  end

  test "preflight reports every conflicting identity before any mutation" do
    create_legacy_schema
    insert(:users, id: 1, email: " Person@Example.test ", oauth_provider: nil, oauth_uid: nil)
    insert(:users, id: 2, email: "person@example.TEST", oauth_provider: nil, oauth_uid: nil)
    insert(:users, id: 3, email: "half@example.test", oauth_provider: "github", oauth_uid: nil)
    insert(:users, id: 4, email: "oauth-one@example.test", oauth_provider: " GitHub ", oauth_uid: " shared ")
    insert(:users, id: 5, email: "oauth-two@example.test", oauth_provider: "github", oauth_uid: "shared")
    insert(:users, id: 6, email: " ", oauth_provider: nil, oauth_uid: nil)
    insert(:projects, id: 10, user_id: 1)
    insert(:project_invitations, id: 20, project_id: 10, inviter_id: 1,
      email: " Invitee@Example.test ", status: 0)
    insert(:project_invitations, id: 21, project_id: 10, inviter_id: 1,
      email: "invitee@example.TEST", status: 0)
    insert(:project_invitations, id: 22, project_id: 10, inviter_id: 1,
      email: " ", status: 1)
    insert(:project_invitations, id: 23, project_id: 10, inviter_id: 1,
      email: "status@example.test", status: 9)

    error = assert_raises(ActiveRecord::MigrationError) { run_migration }

    assert_match(/duplicate normalized user emails.*1,2/i, error.message)
    assert_match(/half-populated OAuth identity user IDs: 3/i, error.message)
    assert_match(/duplicate OAuth identities.*4,5/i, error.message)
    assert_match(/blank normalized user email IDs: 6/i, error.message)
    assert_match(/duplicate normalized pending invitations.*20,21/i, error.message)
    assert_match(/blank normalized invitation email IDs: 22/i, error.message)
    assert_match(/invalid invitation status IDs: 23/i, error.message)
    assert_not @connection.column_exists?(:users, :access_status)
    assert_not @connection.table_exists?(:installation_audit_events)
    assert_equal " Person@Example.test ", row(:users, 1).fetch("email")
    assert_equal " Invitee@Example.test ", row(:project_invitations, 20).fetch("email")
  end

  test "database constraints enforce canonical identities and durable invitation states" do
    create_legacy_schema
    insert_valid_graph
    run_migration

    assert_statement_invalid do
      insert(:users, id: 3, email: "Mixed@Example.test", access_status: 0)
    end
    assert_statement_invalid do
      insert(:users, id: 3, email: "new@example.test", access_status: 7)
    end
    assert_statement_invalid do
      insert(:users, id: 3, email: "new@example.test", access_status: 0,
        oauth_provider: "github", oauth_uid: nil)
    end
    assert_statement_invalid do
      insert(:users, id: 3, email: "new@example.test", access_status: 0,
        oauth_provider: "GitHub", oauth_uid: "uid")
    end

    insert(:project_invitations, id: 22, project_id: 10, inviter_id: 1,
      email: "invitee@example.test", status: 1)
    insert(:project_invitations, id: 23, project_id: 10, inviter_id: 1,
      email: "invitee@example.test", status: 2)
    assert_statement_invalid do
      insert(:project_invitations, id: 24, project_id: 10, inviter_id: 1,
        email: "invitee@example.test", status: 0)
    end
    assert_statement_invalid do
      insert(:project_invitations, id: 25, project_id: 10, inviter_id: 1,
        email: "other@example.test", status: 9)
    end
  end

  test "migration is irreversible and uses an explicit PostgreSQL transaction" do
    assert_raises(ActiveRecord::IrreversibleMigration) do
      capture_io { HardenUserAndInvitationIdentity.new.exec_migration(@connection, :down) }
    end

    skip unless @connection.adapter_name == "PostgreSQL"

    create_legacy_schema
    insert_valid_graph
    run_migration
    assert @connection.column_exists?(:users, :access_status)
  end

  test "a fully applied migration safely re-enters when version bookkeeping was interrupted" do
    create_legacy_schema
    insert_valid_graph
    run_migration
    identities = CHILD_TABLES.to_h { |table| [ table, ids(table) ] }

    run_migration

    assert_equal identities, CHILD_TABLES.to_h { |table| [ table, ids(table) ] }
    assert_equal "owner@example.test", row(:users, 1).fetch("email")
    assert @connection.table_exists?(:installation_audit_events)
  end

  test "a partially applied identity schema fails closed" do
    create_legacy_schema
    insert_valid_graph
    @connection.add_column :users, :access_status, :integer, null: false, default: 0

    error = assert_raises(ActiveRecord::MigrationError) { run_migration }

    assert_includes error.message, "partially applied schema"
    assert_not @connection.table_exists?(:installation_audit_events)
  end

  private

  def create_legacy_schema
    @connection.create_table :users do |table|
      table.string :email, null: false
      table.string :password_digest, null: false, default: "digest"
      table.datetime :confirmed_at
      table.string :oauth_provider
      table.string :oauth_uid
      table.timestamps null: false
    end
    @connection.add_index :users, :email, unique: true

    @connection.create_table(:projects) { |table| table.references :user, null: false }
    @connection.create_table :project_invitations do |table|
      table.references :project, null: false
      table.references :inviter, null: false
      table.string :email, null: false
      table.integer :status, null: false, default: 0
    end
    @connection.add_index :project_invitations, %i[project_id email status],
      name: "index_project_invitations_on_project_id_and_email_and_status"

    @connection.create_table(:sessions) { |table| table.references :user, null: false }
    @connection.create_table :project_memberships do |table|
      table.references :project, null: false
      table.references :user, null: false
    end
    @connection.create_table(:subscriptions) { |table| table.references :user, null: false }
    @connection.create_table(:annotations) { |table| table.references :user, null: false }
    @connection.create_table(:annotation_comments) { |table| table.references :user, null: false }
    @connection.create_table(:api_keys) { |table| table.references :issued_by_user }
    @connection.create_table(:oauth_access_grants) { |table| table.references :resource_owner, null: false }
    @connection.create_table(:oauth_access_tokens) { |table| table.references :resource_owner, null: false }
    @connection.create_table(:oauth_device_grants) { |table| table.references :resource_owner }
    @connection.create_table :installations do |table|
      table.string :singleton_key, null: false
      table.references :administrator
    end

    add_foreign_keys
  end

  def add_foreign_keys
    @connection.add_foreign_key :projects, :users
    @connection.add_foreign_key :project_invitations, :projects
    @connection.add_foreign_key :project_invitations, :users, column: :inviter_id
    @connection.add_foreign_key :sessions, :users, on_delete: :cascade
    @connection.add_foreign_key :project_memberships, :projects
    @connection.add_foreign_key :project_memberships, :users
    @connection.add_foreign_key :subscriptions, :users
    @connection.add_foreign_key :annotations, :users
    @connection.add_foreign_key :annotation_comments, :users
    @connection.add_foreign_key :api_keys, :users, column: :issued_by_user_id
    @connection.add_foreign_key :oauth_access_grants, :users,
      column: :resource_owner_id, on_delete: :cascade
    @connection.add_foreign_key :oauth_access_tokens, :users,
      column: :resource_owner_id, on_delete: :cascade
    @connection.add_foreign_key :oauth_device_grants, :users,
      column: :resource_owner_id, on_delete: :cascade
    @connection.add_foreign_key :installations, :users, column: :administrator_id
  end

  def insert_valid_graph
    now = Time.current
    insert(:users, id: 1, email: " Owner@Example.test ", oauth_provider: " GitHub ",
      oauth_uid: " provider-uid ", created_at: now, updated_at: now)
    insert(:users, id: 2, email: "member@example.test", created_at: now, updated_at: now)
    insert(:projects, id: 10, user_id: 1)
    insert(:project_invitations, id: 20, project_id: 10, inviter_id: 1,
      email: "accepted@example.test", status: 1)
    insert(:project_invitations, id: 21, project_id: 10, inviter_id: 1,
      email: " Invitee@Example.test ", status: 0)
    insert(:sessions, id: 30, user_id: 1)
    insert(:project_memberships, id: 31, project_id: 10, user_id: 2)
    insert(:subscriptions, id: 32, user_id: 1)
    insert(:annotations, id: 33, user_id: 2)
    insert(:annotation_comments, id: 34, user_id: 2)
    insert(:api_keys, id: 35, issued_by_user_id: 1)
    insert(:oauth_access_grants, id: 36, resource_owner_id: 2)
    insert(:oauth_access_tokens, id: 37, resource_owner_id: 2)
    insert(:oauth_device_grants, id: 38, resource_owner_id: 2)
    insert(:installations, id: 39, singleton_key: "screenote", administrator_id: 1)
  end

  def insert(table, **attributes)
    if table == :users
      attributes = {
        password_digest: "digest",
        created_at: Time.current,
        updated_at: Time.current
      }.merge(attributes)
    end
    columns = attributes.keys.map { |column| @connection.quote_column_name(column) }.join(", ")
    values = attributes.values.map { |value| @connection.quote(value) }.join(", ")
    @connection.execute(<<~SQL.squish)
      INSERT INTO #{@connection.quote_table_name(table)} (#{columns}) VALUES (#{values})
    SQL
  end

  def row(table, id)
    @connection.select_one(<<~SQL.squish)
      SELECT * FROM #{@connection.quote_table_name(table)} WHERE id = #{@connection.quote(id)}
    SQL
  end

  def ids(table)
    @connection.select_values(<<~SQL.squish).map(&:to_i)
      SELECT id FROM #{@connection.quote_table_name(table)} ORDER BY id
    SQL
  end

  def index_names(table)
    @connection.indexes(table).map(&:name)
  end

  def assert_constraint(table, name)
    assert_includes @connection.check_constraints(table).map(&:name), name
  end

  def assert_statement_invalid(&block)
    assert_raises(ActiveRecord::StatementInvalid) do
      @connection.transaction(requires_new: true, &block)
    end
  end

  def sqlite_foreign_key_violations
    @connection.select_rows("PRAGMA foreign_key_check")
  end

  def sqlite?
    @connection.adapter_name == "SQLite"
  end

  def run_migration
    capture_io { HardenUserAndInvitationIdentity.new.exec_migration(@connection, :up) }
  end

  def drop_schema
    %i[
      installation_audit_events installations oauth_device_grants oauth_access_tokens
      oauth_access_grants api_keys annotation_comments annotations subscriptions
      sessions project_memberships project_invitations projects users
    ].each { |table| @connection.drop_table(table, if_exists: true, force: :cascade) }
  end

  def migration_database_config
    ENV["MIGRATION_TEST_DATABASE_URL"].presence || { adapter: "sqlite3", database: ":memory:" }
  end
end
