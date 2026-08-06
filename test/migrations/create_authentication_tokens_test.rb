# frozen_string_literal: true

require "test_helper"
require Rails.root.join("db/migrate/20260805133000_create_authentication_tokens").to_s

class CreateAuthenticationTokensTest < ActiveSupport::TestCase
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
    create_subject_schema
  end

  def after_teardown
    drop_schema if @connection
    super
  ensure
    @database_class&.remove_connection
  end

  test "fresh migration creates exact subject, digest, expiry, and terminal constraints" do
    run_migration

    %w[
      authentication_tokens_valid_purpose
      authentication_tokens_exact_subject
      authentication_tokens_positive_generation
      authentication_tokens_derivation_id_length
      authentication_tokens_key_id_format
      authentication_tokens_digest_length
      authentication_tokens_future_expiry
      authentication_tokens_valid_state
      authentication_tokens_terminal_state
    ].each { |name| assert_constraint(name) }

    assert_includes index_names, "index_auth_tokens_on_outstanding_user"
    assert_includes index_names, "index_auth_tokens_on_outstanding_invitation"
    assert_includes index_names, "index_auth_tokens_on_user_generation"
    assert_includes index_names, "index_auth_tokens_on_invitation_generation"
    assert_includes index_names, "index_authentication_tokens_on_state_and_derivation_key_id"

    constraint_sql = @connection.check_constraints(:authentication_tokens).map(&:expression).join("\n")
    assert_not_includes constraint_sql, " GLOB "
    refute_match(/\s~\s/, constraint_sql)
  end

  test "partial indexes enforce one outstanding token and unique generations per exact subject" do
    run_migration
    insert_token(id: 10, purpose: 1, user_id: 1, generation: 1)

    assert_statement_invalid do
      insert_token(id: 11, purpose: 1, user_id: 1, generation: 2)
    end

    terminalize(10)
    insert_token(id: 11, purpose: 1, user_id: 1, generation: 2)
    insert_token(id: 12, purpose: 2, user_id: 1, generation: 1)

    assert_statement_invalid do
      insert_token(id: 13, purpose: 1, user_id: 1, generation: 2,
        state: 2, terminal_at: Time.current)
    end

    insert_token(id: 20, purpose: 0, project_invitation_id: 2, generation: 1)
    assert_statement_invalid do
      insert_token(id: 21, purpose: 0, project_invitation_id: 2, generation: 2)
    end
  end

  test "database rejects wrong subjects malformed public metadata and invalid terminal states" do
    run_migration

    assert_statement_invalid { insert_token(id: 10, purpose: 0, user_id: 1) }
    assert_statement_invalid { insert_token(id: 11, purpose: 1, project_invitation_id: 2) }
    assert_statement_invalid do
      insert_token(id: 12, purpose: 1, user_id: 1, project_invitation_id: 2)
    end
    assert_statement_invalid do
      insert_token(id: 13, purpose: 1, user_id: 1, derivation_id: "A" * 64)
    end
    assert_statement_invalid do
      insert_token(id: 14, purpose: 1, user_id: 1, token_digest: "g" * 64)
    end
    assert_statement_invalid do
      insert_token(id: 19, purpose: 1, user_id: 1,
        derivation_key_id: "v1.#{'A' * 42}.")
    end
    assert_statement_invalid do
      insert_token(id: 15, purpose: 1, user_id: 1, state: 1, terminal_at: nil)
    end
    assert_statement_invalid do
      insert_token(id: 16, purpose: 1, user_id: 1, state: 0, terminal_at: Time.current)
    end
    assert_statement_invalid do
      insert_token(id: 17, purpose: 1, user_id: 1, state: 1,
        created_at: Time.current, terminal_at: 1.minute.ago)
    end
    assert_statement_invalid do
      insert_token(id: 18, purpose: 1, user_id: 1,
        created_at: Time.current, expires_at: 1.minute.ago)
    end
  end

  private

  def create_subject_schema
    @connection.create_table(:users) { |table| table.string :email }
    @connection.create_table(:projects) { |table| table.references :user, null: false }
    @connection.create_table :project_invitations do |table|
      table.references :project, null: false
      table.references :inviter, null: false
      table.string :email, null: false
      table.integer :status, null: false, default: 0
    end
    @connection.add_foreign_key :projects, :users
    @connection.add_foreign_key :project_invitations, :projects
    @connection.add_foreign_key :project_invitations, :users, column: :inviter_id

    insert(:users, id: 1, email: "owner@example.test")
    insert(:projects, id: 1, user_id: 1)
    insert(:project_invitations, id: 2, project_id: 1, inviter_id: 1,
      email: "invitee@example.test", status: 0)
  end

  def insert_token(id:, purpose:, user_id: nil, project_invitation_id: nil, generation: 1,
    derivation_id: nil, derivation_key_id: nil, token_digest: nil,
    state: 0, terminal_at: nil, created_at: nil, expires_at: nil)
    created_at ||= Time.current
    expires_at ||= created_at + 15.minutes
    insert(:authentication_tokens,
      id: id,
      purpose: purpose,
      user_id: user_id,
      project_invitation_id: project_invitation_id,
      generation: generation,
      derivation_id: derivation_id || format("%064x", id * 3),
      derivation_key_id: derivation_key_id || "v1.#{'A' * 41}_-",
      token_digest: token_digest || format("%064x", id * 5),
      expires_at: expires_at,
      state: state,
      terminal_at: terminal_at,
      created_at: created_at,
      updated_at: created_at)
  end

  def terminalize(id)
    now = Time.current
    @connection.execute(<<~SQL.squish)
      UPDATE authentication_tokens
      SET state = 2, terminal_at = #{@connection.quote(now)}, updated_at = #{@connection.quote(now)}
      WHERE id = #{@connection.quote(id)}
    SQL
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

  def assert_constraint(name)
    assert_includes @connection.check_constraints(:authentication_tokens).map(&:name), name
  end

  def index_names
    @connection.indexes(:authentication_tokens).map(&:name)
  end

  def run_migration
    capture_io do
      @connection.transaction do
        CreateAuthenticationTokens.new.exec_migration(@connection, :up)
      end
    end
  end

  def drop_schema
    %i[authentication_tokens project_invitations projects users].each do |table|
      @connection.drop_table(table, if_exists: true, force: :cascade)
    end
  end

  def migration_database_config
    ENV["MIGRATION_TEST_DATABASE_URL"].presence || { adapter: "sqlite3", database: ":memory:" }
  end
end
