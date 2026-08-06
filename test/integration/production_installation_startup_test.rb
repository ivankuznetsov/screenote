# frozen_string_literal: true

# screenote-edition: self_hosted

require "test_helper"
require "json"
require "open3"
require "tmpdir"

class ProductionInstallationStartupTest < ActiveSupport::TestCase
  RUNTIME_KEYS = %w[
    SCREENOTE_EDITION SCREENOTE_BASE_URL SCREENOTE_BOOTSTRAP_TOKEN SCREENOTE_TRUSTED_PROXIES
    SCREENOTE_STORAGE SCREENOTE_SMTP_ENABLED SCREENOTE_GOOGLE_OAUTH_ENABLED
    SCREENOTE_GITHUB_OAUTH_ENABLED SCREENOTE_HONEYBADGER_ENABLED
    SCREENOTE_S3_ENDPOINT SCREENOTE_S3_REGION SCREENOTE_S3_BUCKET SCREENOTE_S3_PREFIX
    SCREENOTE_S3_ACCESS_KEY_ID SCREENOTE_S3_SECRET_ACCESS_KEY SCREENOTE_S3_PATH_STYLE
    SCREENOTE_S3_REQUEST_TIMEOUT SCREENOTE_S3_RETRY_LIMIT
    DATABASE_URL CACHE_DATABASE_URL QUEUE_DATABASE_URL CABLE_DATABASE_URL
    STRIPE_SECRET_KEY STRIPE_WEBHOOK_SECRET STRIPE_PRO_PRICE_ID RESEND_API_KEY MAILER_FROM
    GOOGLE_CLIENT_ID GOOGLE_CLIENT_SECRET GITHUB_CLIENT_ID GITHUB_CLIENT_SECRET
    HONEYBADGER_API_KEY HONEYBADGER_JS_API_KEY RABATA_ENDPOINT RABATA_REGION RABATA_BUCKET
    RABATA_ACCESS_KEY_ID RABATA_SECRET_ACCESS_KEY SCREENOTE_SAAS_OPERATOR_EMAIL
    SECRET_KEY_BASE SECRET_KEY_BASE_DUMMY
  ].freeze

  STARTUP_PROBE = <<~'RUBY'.freeze
    root = ENV.fetch("SCREENOTE_TEST_DATABASE_ROOT")
    role_migrations = {
      "primary" => nil,
      "cache" => "db/cache_migrate",
      "queue" => "db/queue_migrate",
      "cable" => "db/cable_migrate"
    }
    configs = role_migrations.map do |role, migrations_path|
      configuration = {
        adapter: "sqlite3",
        database: File.join(root, "#{role}.sqlite3"),
        timeout: 5_000,
        pragmas: { journal_mode: :wal, synchronous: :full, foreign_keys: true }
      }
      configuration[:migrations_paths] = migrations_path if migrations_path
      ActiveRecord::DatabaseConfigurations::HashConfig.new("production", role, configuration)
    end
    ActiveRecord::Base.connection_handler.clear_all_connections!(:all)
    ActiveRecord::Base.configurations = configs
    ActiveRecord::Base.establish_connection(:primary)
    ActiveRecord::Tasks::DatabaseTasks.prepare_all

    begin
      installation = Installations::Prepare.call
      result = {
        outcome: "ok",
        id: installation.id,
        deployment_mode: installation.deployment_mode,
        storage_service: installation.storage_service,
        fingerprint: installation.storage_namespace_fingerprint,
        count: Installation.count
      }
    rescue Installations::Prepare::ConfigurationMismatch => error
      result = {
        outcome: "configuration_mismatch",
        error: error.message,
        count: Installation.count,
        persisted_mode: Installation.current&.deployment_mode,
        persisted_storage: Installation.current&.storage_service,
        persisted_fingerprint: Installation.current&.storage_namespace_fingerprint
      }
    end
    puts(result.to_json)
  RUBY

  test "independent self hosted starts preserve identity and reject namespace drift" do
    Dir.mktmpdir("screenote-installation-startup") do |directory|
      created = start_with(directory, self_hosted_environment)
      assert_equal "ok", created.fetch("outcome")
      assert_equal "self_hosted", created.fetch("deployment_mode")
      assert_equal "self_hosted_local", created.fetch("storage_service")
      assert_equal 1, created.fetch("count")

      restarted = start_with(directory, self_hosted_environment)
      assert_equal created.slice("id", "fingerprint"), restarted.slice("id", "fingerprint")
      assert_equal 1, restarted.fetch("count")

      wrong_storage = start_with(directory, self_hosted_s3_environment)
      assert_equal "configuration_mismatch", wrong_storage.fetch("outcome")
      assert_includes wrong_storage.fetch("error"), "storage service"
      assert_equal "self_hosted_local", wrong_storage.fetch("persisted_storage")
      assert_equal created.fetch("fingerprint"), wrong_storage.fetch("persisted_fingerprint")
    end
  end

  test "a fresh production primary stays empty without bootstrap material" do
    Dir.mktmpdir("screenote-installation-bootstrap") do |directory|
      payload = start_with(
        directory,
        self_hosted_environment.except("SCREENOTE_BOOTSTRAP_TOKEN")
      )

      assert_equal "configuration_mismatch", payload.fetch("outcome")
      assert_includes payload.fetch("error"), "bootstrap"
      assert_equal 0, payload.fetch("count")
    end
  end

  private

  def start_with(directory, environment)
    stdout, stderr, status = Open3.capture3(
      clean_environment.merge(environment).merge("SCREENOTE_TEST_DATABASE_ROOT" => directory),
      "bin/rails", "runner", STARTUP_PROBE,
      chdir: Rails.root.to_s
    )

    assert status.success?, stderr
    json_line = stdout.lines.reverse.find { |line| line.lstrip.start_with?("{") }
    assert json_line, "expected startup JSON in stdout:\n#{stdout}"
    JSON.parse(json_line)
  end

  def clean_environment
    runtime_keys.to_h { |key| [ key, nil ] }.merge(
      "RAILS_ENV" => "production",
      "RAILS_LOG_TO_STDOUT" => nil
    )
  end

  def runtime_keys
    RUNTIME_KEYS
  end

  def self_hosted_environment
    {
      "SCREENOTE_EDITION" => "self_hosted",
      "SCREENOTE_BASE_URL" => "http://screenote.internal:3005",
      "SECRET_KEY_BASE" => "a" * 64,
      "SCREENOTE_BOOTSTRAP_TOKEN" => "b" * 43
    }
  end

  def self_hosted_s3_environment
    self_hosted_environment.merge(
      "SCREENOTE_STORAGE" => "s3",
      "SCREENOTE_S3_ENDPOINT" => "https://objects.example.test",
      "SCREENOTE_S3_REGION" => "local",
      "SCREENOTE_S3_BUCKET" => "screenote-private",
      "SCREENOTE_S3_PREFIX" => "team-one",
      "SCREENOTE_S3_ACCESS_KEY_ID" => "test-access",
      "SCREENOTE_S3_SECRET_ACCESS_KEY" => "test-secret"
    )
  end
end
