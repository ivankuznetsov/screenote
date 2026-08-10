# frozen_string_literal: true

require "test_helper"
require "digest"
require "fileutils"
require "tmpdir"

class ScreenoteDeploymentPreflightTest < ActiveSupport::TestCase
  test "unsupported or incomplete edition fails before storage inspection" do
    Dir.mktmpdir("screenote-deployment-preflight") do |storage_root|
      error = assert_raises(Screenote::DeploymentPreflight::Mismatch) do
        preflight(storage_root: storage_root, environment: { "SCREENOTE_EDITION" => "enterprise" })
      end
      assert_equal "SCREENOTE_EDITION must be saas or self_hosted", error.message

      error = assert_raises(Screenote::DeploymentPreflight::Mismatch) do
        preflight(storage_root: storage_root, environment: { "SCREENOTE_EDITION" => "self_hosted" })
      end
      assert_match(/SECRET_KEY_BASE/, error.message)
      assert_empty Dir.children(storage_root)
    end
  end

  test "matching self hosted identity is inspected without mutation" do
    Dir.mktmpdir("screenote-deployment-preflight") do |storage_root|
      database_path = create_primary(storage_root)
      before = Digest::SHA256.file(database_path).hexdigest

      assert_equal :ok, preflight(storage_root: storage_root)
      assert_equal before, Digest::SHA256.file(database_path).hexdigest
    end
  end

  test "SaaS selection rejects a durable self hosted primary before database preparation" do
    Dir.mktmpdir("screenote-deployment-preflight") do |storage_root|
      database_path = create_primary(storage_root)
      before = Digest::SHA256.file(database_path).hexdigest

      error = assert_raises(Screenote::DeploymentPreflight::Mismatch) do
        preflight(storage_root: storage_root, environment: { "SCREENOTE_EDITION" => "saas" })
      end

      assert_match(/self-hosted primary/, error.message)
      assert_match(/configured edition is saas/, error.message)
      assert_equal before, Digest::SHA256.file(database_path).hexdigest
    end
  end

  test "self hosted selection rejects retained SaaS database configuration without connecting" do
    Dir.mktmpdir("screenote-deployment-preflight") do |storage_root|
      sentinel = "postgres-password-must-not-leak"
      error = assert_raises(Screenote::DeploymentPreflight::Mismatch) do
        Screenote::DeploymentPreflight.call(
          environment: {
            "SCREENOTE_EDITION" => "self_hosted",
            "DATABASE_URL" => "postgres://screenote:#{sentinel}@database.example/screenote",
            "CACHE_DATABASE_URL" => "postgres://screenote:#{sentinel}@database.example/cache"
          },
          storage_root: storage_root
        )
      end

      assert_match(/DATABASE_URL, CACHE_DATABASE_URL/, error.message)
      assert_not_includes error.message, sentinel
      assert_empty Dir.children(storage_root)
    end
  end

  test "self hosted selection rejects a conflicting persisted installation mode" do
    Dir.mktmpdir("screenote-deployment-preflight") do |storage_root|
      database_path = create_primary(storage_root, deployment_mode: "saas")
      before = Digest::SHA256.file(database_path).hexdigest

      error = assert_raises(Screenote::DeploymentPreflight::Mismatch) do
        preflight(storage_root: storage_root)
      end

      assert_match(/does not match self_hosted/, error.message)
      assert_equal before, Digest::SHA256.file(database_path).hexdigest
    end
  end

  test "storage service drift is rejected without mutating a pending primary" do
    assert_identity_mismatch_without_mutation(
      configured_environment: self_hosted_s3_environment,
      message: /storage service/
    )
  end

  test "storage namespace drift is rejected without mutating a pending primary" do
    persisted_environment = self_hosted_s3_environment
    configured_environment = persisted_environment.merge("SCREENOTE_S3_PREFIX" => "team-two")

    assert_identity_mismatch_without_mutation(
      persisted_environment: persisted_environment,
      configured_environment: configured_environment,
      message: /storage namespace/
    )
  end

  test "claimed installation identity is accepted without setup credentials" do
    Dir.mktmpdir("screenote-deployment-preflight") do |storage_root|
      database_path = create_primary(storage_root, state: "claimed")
      before = Digest::SHA256.file(database_path).hexdigest

      assert_equal :ok, preflight(storage_root: storage_root)
      assert_equal before, Digest::SHA256.file(database_path).hexdigest
    end
  end

  test "fresh topologies pass and malformed local state fails closed" do
    Dir.mktmpdir("screenote-deployment-preflight") do |storage_root|
      assert_equal :ok, preflight(storage_root: storage_root)
      assert_equal :ok, preflight(
        storage_root: storage_root,
        environment: { "SCREENOTE_EDITION" => "saas" }
      )

      File.binwrite(File.join(storage_root, "primary.sqlite3"), "not a database")
      error = assert_raises(Screenote::DeploymentPreflight::Mismatch) do
        preflight(storage_root: storage_root)
      end
      assert_match(/cannot verify/, error.message)
    end
  end

  test "non-regular or symlinked primary paths fail closed" do
    Dir.mktmpdir("screenote-deployment-preflight") do |storage_root|
      FileUtils.mkdir_p(File.join(storage_root, "primary.sqlite3"))

      error = assert_raises(Screenote::DeploymentPreflight::Mismatch) do
        preflight(storage_root: storage_root)
      end
      assert_equal "cannot verify existing self-hosted primary", error.message
    end

    Dir.mktmpdir("screenote-deployment-preflight") do |storage_root|
      target = File.join(storage_root, "actual.sqlite3")
      File.binwrite(target, "not opened through a link")
      File.symlink(target, File.join(storage_root, "primary.sqlite3"))

      error = assert_raises(Screenote::DeploymentPreflight::Mismatch) do
        preflight(storage_root: storage_root)
      end
      assert_equal "cannot verify existing self-hosted primary", error.message
    end
  end

  test "pre-schema and empty installation tables are accepted without mutation" do
    Dir.mktmpdir("screenote-deployment-preflight") do |storage_root|
      path = File.join(storage_root, "primary.sqlite3")
      database = SQLite3::Database.new(path)
      database.execute("CREATE TABLE schema_migrations (version varchar NOT NULL PRIMARY KEY)")
      database.close
      before = Digest::SHA256.file(path).hexdigest

      assert_equal :ok, preflight(storage_root: storage_root)
      assert_equal before, Digest::SHA256.file(path).hexdigest
    end

    Dir.mktmpdir("screenote-deployment-preflight") do |storage_root|
      path = File.join(storage_root, "primary.sqlite3")
      database = SQLite3::Database.new(path)
      database.execute(<<~SQL)
        CREATE TABLE installations (
          singleton_key varchar NOT NULL,
          deployment_mode varchar NOT NULL,
          storage_service varchar NOT NULL,
          storage_namespace_fingerprint varchar NOT NULL,
          state varchar NOT NULL
        )
      SQL
      database.close
      before = Digest::SHA256.file(path).hexdigest

      assert_equal :ok, preflight(storage_root: storage_root)
      assert_equal before, Digest::SHA256.file(path).hexdigest
    end
  end

  test "unknown persisted ownership state is rejected without mutation" do
    Dir.mktmpdir("screenote-deployment-preflight") do |storage_root|
      path = create_primary(storage_root, state: "claimed")
      database = SQLite3::Database.new(path)
      database.execute("UPDATE installations SET state = 'retired'")
      database.close
      before = Digest::SHA256.file(path).hexdigest

      error = assert_raises(Screenote::DeploymentPreflight::Mismatch) do
        preflight(storage_root: storage_root)
      end
      assert_match(/ownership state is invalid/, error.message)
      assert_equal before, Digest::SHA256.file(path).hexdigest
    end
  end

  private

  def preflight(storage_root:, environment: self_hosted_environment)
    Screenote::DeploymentPreflight.call(
      environment: environment,
      storage_root: storage_root
    )
  end

  def create_primary(storage_root, deployment_mode: "self_hosted", state: "unclaimed",
    environment: self_hosted_environment)
    deployment = Screenote::Deployment.new(environment, production: true)
    path = File.join(storage_root, "primary.sqlite3")
    database = SQLite3::Database.new(path)
    database.execute(<<~SQL)
      CREATE TABLE installations (
        singleton_key varchar NOT NULL,
        deployment_mode varchar NOT NULL,
        storage_service varchar NOT NULL,
        storage_namespace_fingerprint varchar NOT NULL,
        state varchar NOT NULL
      )
    SQL
    database.execute(
      <<~SQL,
        INSERT INTO installations (
          singleton_key, deployment_mode, storage_service,
          storage_namespace_fingerprint, state
        ) VALUES (?, ?, ?, ?, ?)
      SQL
      [
        "screenote",
        deployment_mode,
        deployment.active_storage_service.to_s,
        deployment.storage_namespace_fingerprint,
        state
      ]
    )
    database.execute("CREATE TABLE schema_migrations (version varchar NOT NULL PRIMARY KEY)")
    database.execute("INSERT INTO schema_migrations (version) VALUES ('20260805110000')")
    path
  ensure
    database&.close
  end

  def assert_identity_mismatch_without_mutation(configured_environment:, message:,
    persisted_environment: self_hosted_environment)
    Dir.mktmpdir("screenote-deployment-preflight") do |storage_root|
      database_path = create_primary(storage_root, environment: persisted_environment)
      before = Digest::SHA256.file(database_path).hexdigest

      error = assert_raises(Screenote::DeploymentPreflight::Mismatch) do
        preflight(storage_root: storage_root, environment: configured_environment)
      end

      assert_match message, error.message
      assert_equal before, Digest::SHA256.file(database_path).hexdigest
    end
  end

  def self_hosted_environment
    {
      "SCREENOTE_EDITION" => "self_hosted",
      "SCREENOTE_BASE_URL" => "http://screenote.internal:3005",
      "SECRET_KEY_BASE" => "a" * 64
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
