# frozen_string_literal: true

require "test_helper"
require Rails.root.join("db/migrate/20260805130000_add_api_key_issuers_and_annotation_actors").to_s

class AddApiKeyIssuersAndAnnotationActorsTest < ActiveSupport::TestCase
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

  test "revokes legacy keys without fabricating issuer provenance and preserves valid actors" do
    create_legacy_schema
    insert_valid_legacy_graph

    run_migration

    api_key_columns = @connection.columns(:api_keys).index_by(&:name)
    annotation_columns = @connection.columns(:annotations).index_by(&:name)
    assert_equal true, api_key_columns.fetch("issued_by_user_id").null
    assert_equal true, annotation_columns.fetch("user_id").null
    assert_equal true, annotation_columns.fetch("api_key_id").null
    legacy_key = @connection.select_one("SELECT issued_by_user_id, revoked_at FROM api_keys WHERE id = 20")
    assert_nil legacy_key.fetch("issued_by_user_id")
    assert legacy_key.fetch("revoked_at").present?
    assert_equal 2, @connection.select_value("SELECT user_id FROM annotations WHERE id = 40").to_i
    assert_nil @connection.select_value("SELECT api_key_id FROM annotations WHERE id = 40")
    assert_equal 20, @connection.select_value("SELECT resolved_by_api_key_id FROM annotations WHERE id = 41").to_i
    assert_equal 20, @connection.select_value("SELECT api_key_id FROM annotation_comments WHERE id = 51").to_i

    assert_foreign_key :api_keys, :users, "issued_by_user_id"
    assert_foreign_key :annotations, :api_keys, "api_key_id"
    assert_check_constraint :api_keys, "api_keys_active_requires_issuer"
    assert_check_constraint :annotations, "annotations_exactly_one_actor"
    assert_check_constraint :annotations, "annotations_resolution_actor_state"
    assert_check_constraint :annotation_comments, "annotation_comments_exactly_one_actor"
  end

  test "database constraints reject invalid actor and resolution states" do
    create_legacy_schema
    insert_valid_legacy_graph
    run_migration

    assert_statement_invalid do
      insert(:api_keys,
        id: 21, project_id: 10, issued_by_user_id: nil, token_digest: "active-missing-issuer",
        name: "Active missing issuer", revoked_at: nil)
    end
    insert(:api_keys,
      id: 22, project_id: 10, issued_by_user_id: nil, token_digest: "revoked-missing-issuer",
      name: "Revoked legacy key", revoked_at: Time.current)
    assert_nil @connection.select_value("SELECT issued_by_user_id FROM api_keys WHERE id = 22")
    assert @connection.select_value("SELECT revoked_at FROM api_keys WHERE id = 22").present?
    insert(:api_keys,
      id: 23, project_id: 10, issued_by_user_id: 1, token_digest: "active-known-issuer",
      name: "Active known issuer", revoked_at: nil)
    assert_statement_invalid do
      insert(:api_keys,
        id: 24, project_id: 10, issued_by_user_id: 999, token_digest: "unknown-issuer", name: "Unknown issuer")
    end

    assert_statement_invalid do
      insert_annotation(id: 42, user_id: nil, api_key_id: nil, status: 0)
    end
    assert_statement_invalid do
      insert_annotation(id: 43, user_id: 2, api_key_id: 20, status: 0)
    end
    assert_statement_invalid do
      insert_annotation(id: 44, user_id: 2, api_key_id: nil, status: 1)
    end
    assert_statement_invalid do
      insert_annotation(id: 45, user_id: 2, api_key_id: nil, status: 0, resolved_by_user_id: 2)
    end

    insert_annotation(id: 46, user_id: nil, api_key_id: 20, status: 0)
    insert_annotation(id: 47, user_id: nil, api_key_id: 20, status: 1, resolved_by_api_key_id: 20)

    assert_statement_invalid do
      insert_comment(id: 52, annotation_id: 40, user_id: nil, api_key_id: nil)
    end
    assert_statement_invalid do
      insert_comment(id: 53, annotation_id: 40, user_id: 2, api_key_id: 20)
    end
    insert_comment(id: 54, annotation_id: 40, user_id: nil, api_key_id: 20)
  end

  test "preflight reports every invalid legacy actor before changing the schema" do
    create_legacy_schema
    insert_valid_legacy_graph
    insert_annotation(id: 42, user_id: nil, api_key_id: nil, status: 0)
    insert_annotation(id: 43, user_id: 2, api_key_id: nil, status: 1)
    insert_comment(id: 52, annotation_id: 40, user_id: 2, api_key_id: 20)

    error = assert_raises(ActiveRecord::MigrationError) { run_migration }

    assert_match(/annotations actor.*42/i, error.message)
    assert_match(/annotations resolution.*43/i, error.message)
    assert_match(/annotation_comments actor.*52/i, error.message)
    assert_legacy_schema_unmodified
  end

  test "is irreversible because legacy revocation and actor provenance cannot be reversed" do
    assert_raises(ActiveRecord::IrreversibleMigration) do
      capture_io { AddApiKeyIssuersAndAnnotationActors.new.exec_migration(@connection, :down) }
    end
  end

  private

  def create_legacy_schema
    @connection.create_table(:users) { |table| table.string :email }
    @connection.create_table(:projects) { |table| table.references :user, null: false }
    @connection.create_table :api_keys do |table|
      table.references :project, null: false
      table.string :token_digest, null: false
      table.string :name, null: false
      table.datetime :revoked_at
    end
    @connection.create_table(:screenshots) { |table| table.string :title }
    @connection.create_table :annotations do |table|
      table.references :screenshot, null: false
      table.references :user
      table.references :resolved_by_user
      table.references :resolved_by_api_key
      table.integer :status, default: 0, null: false
      table.float :x_percent, null: false
      table.float :y_percent, null: false
      table.text :comment
    end
    @connection.create_table :annotation_comments do |table|
      table.references :annotation, null: false
      table.references :user
      table.references :api_key
      table.text :body, null: false
      table.integer :action, default: 0, null: false
    end

    @connection.add_foreign_key :projects, :users
    @connection.add_foreign_key :api_keys, :projects
    @connection.add_foreign_key :annotations, :screenshots
    @connection.add_foreign_key :annotations, :users
    @connection.add_foreign_key :annotations, :users,
      column: :resolved_by_user_id, on_delete: :nullify
    @connection.add_foreign_key :annotations, :api_keys,
      column: :resolved_by_api_key_id, on_delete: :nullify
    @connection.add_foreign_key :annotation_comments, :annotations, on_delete: :cascade
    @connection.add_foreign_key :annotation_comments, :users, on_delete: :nullify
    @connection.add_foreign_key :annotation_comments, :api_keys, on_delete: :nullify
  end

  def insert_valid_legacy_graph
    insert(:users, id: 1, email: "owner@example.test")
    insert(:users, id: 2, email: "reviewer@example.test")
    insert(:projects, id: 10, user_id: 1)
    insert(:api_keys, id: 20, project_id: 10, token_digest: "legacy-key", name: "Legacy key")
    insert(:screenshots, id: 30, title: "Settings")
    insert_annotation(id: 40, user_id: 2, api_key_id: nil, status: 0)
    insert_annotation(id: 41, user_id: 2, api_key_id: nil, status: 1, resolved_by_api_key_id: 20)
    insert_comment(id: 50, annotation_id: 40, user_id: 2, api_key_id: nil)
    insert_comment(id: 51, annotation_id: 41, user_id: nil, api_key_id: 20)
  end

  def insert_annotation(id:, user_id:, api_key_id:, status:, resolved_by_user_id: nil,
    resolved_by_api_key_id: nil)
    attributes = {
      id: id,
      screenshot_id: 30,
      user_id: user_id,
      status: status,
      x_percent: 10.0,
      y_percent: 20.0,
      comment: "Feedback",
      resolved_by_user_id: resolved_by_user_id,
      resolved_by_api_key_id: resolved_by_api_key_id
    }
    attributes[:api_key_id] = api_key_id if @connection.column_exists?(:annotations, :api_key_id)
    insert(:annotations, **attributes)
  end

  def insert_comment(id:, annotation_id:, user_id:, api_key_id:)
    insert(:annotation_comments,
      id: id, annotation_id: annotation_id, user_id: user_id, api_key_id: api_key_id,
      body: "Thread reply", action: 0)
  end

  def insert(table, **attributes)
    columns = attributes.keys.map { |column| @connection.quote_column_name(column) }.join(", ")
    values = attributes.values.map { |value| @connection.quote(value) }.join(", ")
    @connection.execute(<<~SQL.squish)
      INSERT INTO #{@connection.quote_table_name(table)} (#{columns}) VALUES (#{values})
    SQL
  end

  def assert_statement_invalid(&block)
    assert_raises(ActiveRecord::StatementInvalid, &block)
  end

  def assert_foreign_key(from_table, to_table, column)
    assert @connection.foreign_keys(from_table).any? { |key|
      key.to_table == to_table.to_s && key.options.fetch(:column).to_s == column
    }, "Expected #{from_table}.#{column} to reference #{to_table}"
  end

  def assert_check_constraint(table, name)
    assert_includes @connection.check_constraints(table).map(&:name), name
  end

  def assert_legacy_schema_unmodified
    assert_not @connection.column_exists?(:api_keys, :issued_by_user_id)
    assert_not @connection.column_exists?(:annotations, :api_key_id)
    assert_nil @connection.select_value("SELECT revoked_at FROM api_keys WHERE id = 20")
  end

  def run_migration
    capture_io do
      @connection.transaction do
        AddApiKeyIssuersAndAnnotationActors.new.exec_migration(@connection, :up)
      end
    end
  end

  def drop_legacy_schema
    %i[annotation_comments annotations api_keys screenshots projects users].each do |table|
      @connection.drop_table(table, if_exists: true)
    end
  end

  def migration_database_config
    ENV["MIGRATION_TEST_DATABASE_URL"].presence || { adapter: "sqlite3", database: ":memory:" }
  end
end
