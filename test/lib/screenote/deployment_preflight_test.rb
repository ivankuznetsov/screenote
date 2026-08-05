# frozen_string_literal: true

require "test_helper"
require "digest"
require "fileutils"
require "tmpdir"

class ScreenoteDeploymentPreflightTest < ActiveSupport::TestCase
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

  test "unclaimed bootstrap drift is rejected without mutating a pending primary" do
    assert_identity_mismatch_without_mutation(
      configured_environment: self_hosted_environment.merge("SCREENOTE_BOOTSTRAP_TOKEN" => "c" * 43),
      message: /bootstrap material/
    )
  end

  test "claimed installation ignores retired bootstrap configuration" do
    Dir.mktmpdir("screenote-deployment-preflight") do |storage_root|
      database_path = create_primary(storage_root, state: "claimed")
      before = Digest::SHA256.file(database_path).hexdigest

      assert_equal :ok, preflight(
        storage_root: storage_root,
        environment: self_hosted_environment.except("SCREENOTE_BOOTSTRAP_TOKEN")
      )
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
        state varchar NOT NULL,
        bootstrap_token_digest varchar
      )
    SQL
    database.execute(
      <<~SQL,
        INSERT INTO installations (
          singleton_key, deployment_mode, storage_service,
          storage_namespace_fingerprint, state, bootstrap_token_digest
        ) VALUES (?, ?, ?, ?, ?, ?)
      SQL
      [
        "screenote",
        deployment_mode,
        deployment.active_storage_service.to_s,
        deployment.storage_namespace_fingerprint,
        state,
        state == "unclaimed" ? deployment.bootstrap_token_digest : nil
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
