# frozen_string_literal: true

# screenote-edition: self_hosted

require "test_helper"
require "erb"
require "json"
require "open3"
require "puma"
require "puma/configuration"
require "tmpdir"
require "yaml"

class SelfHostedDatabaseConfigurationTest < ActiveSupport::TestCase
  self.use_transactional_tests = false

  RoleConnection = Class.new(ActiveRecord::Base) do
    self.abstract_class = true
  end
  ContendingRoleConnection = Class.new(ActiveRecord::Base) do
    self.abstract_class = true
  end

  ROLES = %w[primary cache queue cable].freeze
  ROLE_TABLES = {
    "primary" => "users",
    "cache" => "solid_cache_entries",
    "queue" => "solid_queue_jobs",
    "cable" => "solid_cable_messages"
  }.freeze

  PREPARE_PROBE = <<~'RUBY'.freeze
    root = ENV.fetch("SCREENOTE_TEST_STORAGE_ROOT")
    configs = ActiveRecord::Base.configurations.configurations.map do |config|
      next config unless config.env_name == "production"

      hash = config.configuration_hash.except(:url).merge(
        database: File.join(root, "#{config.name}.sqlite3")
      )
      ActiveRecord::DatabaseConfigurations::HashConfig.new(config.env_name, config.name, hash)
    end
    ActiveRecord::Base.connection_handler.clear_all_connections!(:all)
    ActiveRecord::Base.configurations = configs
    ActiveRecord::Base.establish_connection(:primary)
    ActiveRecord::Tasks::DatabaseTasks.prepare_all
    first_files = Dir.children(root).grep(/\.sqlite3\z/).sort
    first_users = User.count
    ActiveRecord::Tasks::DatabaseTasks.prepare_all
    puts({ files: first_files, users: first_users, users_after_second_prepare: User.count }.to_json)
  RUBY

  test "self hosted production selects four durable SQLite role files" do
    configs = production_configuration("self_hosted")

    assert_equal ROLES, configs.keys
    assert_equal ROLES.map { |role| "/rails/storage/#{role}.sqlite3" },
      configs.values.map { |config| database_from(config.fetch("url")) }
    assert_equal [ "sqlite3" ], configs.values.map { |config| config.fetch("adapter") }.uniq
    assert_equal [ 5000 ], configs.values.map { |config| config.fetch("timeout") }.uniq
    assert_equal 5, configs.fetch("queue").fetch("pool")
    assert_equal [ 3 ], configs.except("queue").values.map { |config| config.fetch("pool") }.uniq
  end

  test "every self hosted role connection uses the durability and contention pragmas" do
    configs = production_configuration("self_hosted")

    Dir.mktmpdir("screenote-database-configuration") do |directory|
      ROLES.each do |role|
        config = configs.fetch(role).except("url").merge("database" => File.join(directory, "#{role}.sqlite3"))
        RoleConnection.establish_connection(config)
        connection = RoleConnection.connection_pool.lease_connection

        assert_equal "wal", connection.select_value("PRAGMA journal_mode").downcase, role
        assert_equal 2, connection.select_value("PRAGMA synchronous").to_i, role
        assert_equal 1, connection.select_value("PRAGMA foreign_keys").to_i, role
        assert_equal :immediate, connection.raw_connection.instance_variable_get(:@default_transaction_mode), role

        RoleConnection.connection_pool.disconnect!
      end
    end
  end

  test "SQLite lock contention stops at the configured bounded timeout" do
    config = production_configuration("self_hosted").fetch("primary").except("url").merge("timeout" => 100)

    Dir.mktmpdir("screenote-database-lock") do |directory|
      config["database"] = File.join(directory, "primary.sqlite3")
      RoleConnection.establish_connection(config)
      ContendingRoleConnection.establish_connection(config)
      first = RoleConnection.connection_pool.lease_connection
      second = ContendingRoleConnection.connection_pool.lease_connection
      first.execute("CREATE TABLE lock_probe (id INTEGER PRIMARY KEY)")
      first.execute("BEGIN IMMEDIATE")
      first.execute("INSERT INTO lock_probe (id) VALUES (1)")

      started_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      assert_raises(ActiveRecord::StatementInvalid) do
        second.execute("INSERT INTO lock_probe (id) VALUES (2)")
      end
      elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started_at

      assert_operator elapsed, :>=, 0.05
      assert_operator elapsed, :<, 1
    ensure
      first&.execute("ROLLBACK")
      RoleConnection.connection_pool.disconnect!
      ContendingRoleConnection.connection_pool.disconnect!
    end
  end

  test "production database preparation creates every schema, is idempotent, and creates no users" do
    Dir.mktmpdir("screenote-database-prepare") do |directory|
      stdout, stderr, status = Open3.capture3(
        production_environment.merge("SCREENOTE_TEST_STORAGE_ROOT" => directory),
        "bin/rails", "runner", PREPARE_PROBE,
        chdir: Rails.root.to_s
      )

      assert status.success?, stderr
      payload = JSON.parse(stdout.lines.last)
      assert_equal ROLES.map { |role| "#{role}.sqlite3" }.sort, payload.fetch("files")
      assert_equal 0, payload.fetch("users")
      assert_equal 0, payload.fetch("users_after_second_prepare")

      ROLE_TABLES.each do |role, table|
        database = SQLite3::Database.new(File.join(directory, "#{role}.sqlite3"))
        assert_equal table, database.get_first_value(
          "SELECT name FROM sqlite_master WHERE type = 'table' AND name = ?", table
        ), role
      ensure
        database&.close
      end
    end
  end

  test "SaaS production retains four PostgreSQL roles" do
    configs = production_configuration("saas")

    assert_equal ROLES, configs.keys
    assert_equal [ "postgresql" ], configs.values.map { |config| config.fetch("adapter") }.uniq
    assert_equal(
      %w[DATABASE_URL CACHE_DATABASE_URL QUEUE_DATABASE_URL CABLE_DATABASE_URL].map { |key| "postgres://screenote@db/#{key.downcase}" },
      configs.values.map { |config| config.fetch("url") }
    )
  end

  test "self hosted Puma runs one process with its Solid Queue supervisor" do
    with_environment("SCREENOTE_EDITION" => "self_hosted", "SOLID_QUEUE_IN_PUMA" => nil) do
      configuration = Puma::Configuration.new(config_files: [ Rails.root.join("config/puma.rb").to_s ])
      configuration.load
      configuration.clamp

      assert_equal 0, configuration.options[:workers]
      assert_equal 3, configuration.options[:min_threads]
      assert_equal 3, configuration.options[:max_threads]
      plugin_instances = configuration.plugins.instance_variable_get(:@instances)
      assert plugin_instances.any? { |plugin| plugin.respond_to?(:solid_queue_supervisor) }

      queue = ERB.new(Rails.root.join("config/queue.yml").read).result
      worker = YAML.safe_load(queue, aliases: true).fetch("production").fetch("workers").sole
      assert_equal 1, worker.fetch("processes")
      assert_equal 3, worker.fetch("threads")
      queue_pool = production_configuration("self_hosted").fetch("queue").fetch("pool")
      assert_operator queue_pool, :>=, worker.fetch("threads") + 2
    end

    with_environment("SCREENOTE_EDITION" => "saas", "JOB_CONCURRENCY" => "4") do
      queue = ERB.new(Rails.root.join("config/queue.yml").read).result
      worker = YAML.safe_load(queue, aliases: true).fetch("production").fetch("workers").sole
      assert_equal 4, worker.fetch("processes")
      assert_equal 3, worker.fetch("threads")
    end
  end

  private

  def database_from(url)
    URI.parse(url).path
  end

  def production_configuration(edition)
    environment = {
      "SCREENOTE_EDITION" => edition,
      "DATABASE_URL" => "postgres://screenote@db/database_url",
      "CACHE_DATABASE_URL" => "postgres://screenote@db/cache_database_url",
      "QUEUE_DATABASE_URL" => "postgres://screenote@db/queue_database_url",
      "CABLE_DATABASE_URL" => "postgres://screenote@db/cable_database_url"
    }
    environment["RAILS_MAX_THREADS"] = "3" if edition == "self_hosted"

    with_environment(environment) do
      document = ERB.new(Rails.root.join("config/database.yml").read).result
      YAML.safe_load(document, aliases: true).fetch("production")
    end
  end

  def production_environment
    {
      "RAILS_ENV" => "production",
      "SCREENOTE_EDITION" => "self_hosted",
      "SCREENOTE_BASE_URL" => "http://screenote.internal:3005",
      "SECRET_KEY_BASE" => "a" * 64,
      "SCREENOTE_BOOTSTRAP_TOKEN" => "b" * 43,
      "RAILS_LOG_TO_STDOUT" => nil
    }
  end

  def with_environment(values)
    original = values.to_h { |key, _value| [ key, ENV[key] ] }
    values.each { |key, value| ENV[key] = value }
    yield
  ensure
    original.each { |key, value| ENV[key] = value }
  end
end
