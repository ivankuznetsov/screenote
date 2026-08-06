# frozen_string_literal: true

require "test_helper"

class CurrentSaasUpgradeTest < ActiveSupport::TestCase
  self.fixture_table_names = []
  self.use_transactional_tests = false

  FIXTURE_PATH = Rails.root.join("test/fixtures/upgrades/current_saas/fixture.json")
  EXPECTED_MIGRATIONS = %w[
    20260805120000 20260805120500 20260805130000
    20260805131000 20260805132000 20260805133000 20260805134000
  ].freeze

  setup do
    require_upgrade_database!
    @original_database = ActiveRecord::Base.connection_db_config.configuration_hash
    ActiveRecord::Base.connection_handler.clear_all_connections!(:all)
    ActiveRecord::Base.establish_connection(ENV.fetch("SAAS_UPGRADE_DATABASE_URL"))
    assert_equal "PostgreSQL", connection.adapter_name
    reset_database!
  end

  teardown do
    ActiveRecord::Base.connection_handler.clear_all_connections!(:all)
    ActiveRecord::Base.establish_connection(@original_database) if @original_database
  end

  test "production-shaped SaaS graph upgrades without identity or credential loss" do
    fixture = JSON.parse(FIXTURE_PATH.read)
    migration_context.up(fixture.fetch("target_version"))
    insert_fixture(fixture.fetch("records"))
    identities = captured_identities(fixture.fetch("records").keys)

    migration_context.migrate

    assert_equal identities, captured_identities(identities.keys)
    assert_equal EXPECTED_MIGRATIONS, applied_versions & EXPECTED_MIGRATIONS
    assert_equal "owner@example.test", value(:users, 101, :email)
    assert_equal "github", value(:users, 101, :oauth_provider)
    assert_equal "owner-uid", value(:users, 101, :oauth_uid)
    assert_equal "pending@example.test", value(:project_invitations, 501, :email)
    assert value(:api_keys, 901, :revoked_at)
    assert_nil value(:api_keys, 901, :issued_by_user_id)

    expected_digests = {
      [ :oauth_applications, 1001, :secret ] => "application-secret-sentinel",
      [ :oauth_access_grants, 1002, :token ] => "authorization-code-sentinel",
      [ :oauth_access_tokens, 1003, :token ] => "access-token-sentinel",
      [ :oauth_access_tokens, 1003, :refresh_token ] => "refresh-token-sentinel",
      [ :oauth_access_tokens, 1003, :previous_refresh_token ] => "previous-refresh-sentinel"
    }
    expected_digests.each do |(table, id, column), raw|
      assert_equal Digest::SHA256.hexdigest(raw), value(table, id, column)
    end

    serialized_database = all_text_values.join("\n")
    fixture.fetch("secret_sentinels").each do |sentinel|
      assert_not_includes serialized_database, sentinel
    end
    assert connection.table_exists?(:installations)
    assert connection.table_exists?(:authentication_tokens)
  end

  test "credential cutover rolls every migration back when final verification fails and then resumes from raw credentials" do
    fixture = JSON.parse(FIXTURE_PATH.read)
    migration_context.up(fixture.fetch("target_version"))
    insert_fixture(fixture.fetch("records"))
    deployment = Struct.new(:saas?).new(true)
    failing_cutover = Class.new(Screenote::SaasCredentialCutover) do
      private

      def verify_all_migrations_applied!
        super
        raise Screenote::SaasCredentialCutover::Error,
          "injected post-migration verification failure"
      end
    end

    with_cutover_authorization do
      error = assert_raises(Screenote::SaasCredentialCutover::Error) do
        capture_io { failing_cutover.new(deployment:, connection:, migration_context:).call }
      end
      assert_includes error.message, "injected post-migration verification failure"
    end

    assert_empty applied_versions & EXPECTED_MIGRATIONS
    assert_equal "access-token-sentinel", value(:oauth_access_tokens, 1003, :token)
    assert_not connection.column_exists?(:users, :access_status)
    assert_not connection.table_exists?(:authentication_tokens)

    result = with_cutover_authorization do
      result = nil
      capture_io do
        result = Screenote::SaasCredentialCutover.new(deployment:, connection:, migration_context:).call
      end
      result
    end

    assert_equal :migrated, result.status
    assert_equal 4, result.witness_count
    assert_equal EXPECTED_MIGRATIONS, applied_versions & EXPECTED_MIGRATIONS
    assert_equal Digest::SHA256.hexdigest("access-token-sentinel"),
      value(:oauth_access_tokens, 1003, :token)
  end

  private

  def require_upgrade_database!
    required = ENV["SCREENOTE_REQUIRE_SAAS_UPGRADE"] == "1"
    url = ENV["SAAS_UPGRADE_DATABASE_URL"].presence
    if url.nil?
      flunk "SAAS_UPGRADE_DATABASE_URL is required by the matrix" if required
      skip "run through script/release_test_matrix saas-upgrade"
    end
    unless ENV["SCREENOTE_ALLOW_SAAS_UPGRADE_DATABASE_RESET"] == "1"
      flunk "destructive upgrade fixture reset was not explicitly authorized" if required
      skip "set SCREENOTE_ALLOW_SAAS_UPGRADE_DATABASE_RESET=1 for a dedicated test database"
    end

    uri = URI.parse(url)
    database = uri.path.delete_prefix("/")
    assert_includes %w[postgres postgresql], uri.scheme
    assert_match(/(?:test|ci)/, database)
  end

  def connection
    ActiveRecord::Base.connection
  end

  def migration_context
    pool = ActiveRecord::Base.connection_pool
    ActiveRecord::MigrationContext.new(
      Rails.root.join("db/migrate"),
      pool.schema_migration,
      pool.internal_metadata
    )
  end

  def reset_database!
    connection.execute("DROP SCHEMA public CASCADE")
    connection.execute("CREATE SCHEMA public")
  end

  def insert_fixture(records)
    records.each do |table, rows|
      rows.each { |attributes| insert(table, attributes) }
    end
  end

  def insert(table, attributes)
    columns = attributes.keys.map { |column| connection.quote_column_name(column) }.join(", ")
    values = attributes.values.map { |value| connection.quote(value) }.join(", ")
    connection.execute(<<~SQL.squish)
      INSERT INTO #{connection.quote_table_name(table)} (#{columns}) VALUES (#{values})
    SQL
  end

  def captured_identities(tables)
    tables.to_h do |table|
      [ table, connection.select_values(
        "SELECT id FROM #{connection.quote_table_name(table)} ORDER BY id"
      ).map(&:to_i) ]
    end
  end

  def value(table, id, column)
    connection.select_value(<<~SQL.squish)
      SELECT #{connection.quote_column_name(column)}
      FROM #{connection.quote_table_name(table)}
      WHERE id = #{connection.quote(id)}
    SQL
  end

  def applied_versions
    connection.select_values("SELECT version FROM schema_migrations ORDER BY version")
  end

  def all_text_values
    connection.tables.flat_map do |table|
      columns = connection.columns(table).select { |column| %i[string text].include?(column.type) }
      columns.flat_map do |column|
        connection.select_values(<<~SQL.squish).compact.map(&:to_s)
          SELECT #{connection.quote_column_name(column.name)}
          FROM #{connection.quote_table_name(table)}
        SQL
      end
    end
  end


  def with_cutover_authorization
    previous = ENV["SCREENOTE_SAAS_CREDENTIAL_CUTOVER"]
    ENV["SCREENOTE_SAAS_CREDENTIAL_CUTOVER"] = "authorized"
    yield
  ensure
    previous.nil? ? ENV.delete("SCREENOTE_SAAS_CREDENTIAL_CUTOVER") :
      ENV["SCREENOTE_SAAS_CREDENTIAL_CUTOVER"] = previous
  end
end
