# frozen_string_literal: true

# screenote-edition: self_hosted

require "test_helper"
require "base64"
require "digest"
require "fileutils"
require "json"
require "open3"
require "timeout"
require "tmpdir"

class SelfHostedBackupRestoreTest < ActiveSupport::TestCase
  BACKUP = Rails.root.join("script/self_hosted_backup_internal").to_s.freeze
  RESTORE = Rails.root.join("script/self_hosted_restore_internal").to_s.freeze
  IMAGE = "ghcr.io/future-spin/screenote@sha256:#{'a' * 64}".freeze
  RECIPIENT = "age1screenotetest".freeze

  test "creates and restores a finalized encrypted local whole-instance set" do
    with_fixture do |fixture|
      authentication_key_bytes = File.binread(fixture.fetch(:authentication_key))
      stdout, stderr, status = run_backup(fixture)

      assert status.success?, stderr
      assert_equal 0o700, File.stat(fixture.fetch(:backup)).mode & 0o777
      assert_equal %w[COMPLETE configuration.age manifest.json.age secrets.tar.age volume.tar.age],
        Dir.children(fixture.fetch(:backup)).sort
      assert Dir.children(fixture.fetch(:backup)).all? {
        |entry| (File.stat(File.join(fixture.fetch(:backup), entry)).mode & 0o777) == 0o600
      }
      marker = JSON.parse(File.binread(File.join(fixture.fetch(:backup), "COMPLETE")))
      assert_equal "screenote-self-hosted-backup-complete/v2", marker.fetch("schema")
      assert_match(/\A[0-9a-f]{64}\z/, marker.fetch("authentication_key_fingerprint"))
      assert_match(/\A[0-9a-f]{64}\z/, marker.fetch("authentication_hmac_sha256"))
      assert_not_includes stdout, fixture.fetch(:secret)
      assert_not_includes stderr, fixture.fetch(:secret)
      assert_not_includes stdout, authentication_key_bytes
      assert_not_includes stderr, authentication_key_bytes
      Dir.children(fixture.fetch(:backup)).each do |entry|
        assert_not_includes File.binread(File.join(fixture.fetch(:backup), entry)), authentication_key_bytes
      end

      stdout, stderr, status = run_restore(fixture)

      assert status.success?, stderr
      assert_equal "primary-state", File.binread(File.join(fixture.fetch(:restored_volume), "state.txt"))
      assert_equal fixture.fetch(:configuration_bytes),
        File.binread(File.join(fixture.fetch(:operator_destination), ".env"))
      assert_equal fixture.fetch(:secret),
        File.binread(File.join(fixture.fetch(:operator_destination), "secrets", "secret_key_base"))
      assert_equal 0o400,
        File.stat(File.join(fixture.fetch(:operator_destination), "secrets", "secret_key_base")).mode & 0o777
      assert_includes stdout, IMAGE
      assert_not_includes stdout, fixture.fetch(:secret)
      assert_not_includes stderr, fixture.fetch(:secret)
      assert_not_includes stdout, authentication_key_bytes
      assert_not_includes stderr, authentication_key_bytes
      identity_paths = File.readlines(fixture.fetch(:identity_log), chomp: true)
      assert_predicate identity_paths, :any?
      assert identity_paths.all? { |path| path.match?(%r{\A/(?:proc/self|dev)/fd/\d+\z}) }
      assert_empty Dir.glob(File.join(fixture.fetch(:operator_destination), "**", "*identity*"))
    end
  end

  test "authenticates a completed backup host-side and rejects the wrong key" do
    with_fixture do |fixture|
      _stdout, stderr, status = run_backup(fixture)
      assert status.success?, stderr

      marker = Screenote::SelfHosted::BackupSet.authenticate_completion!(
        source: fixture.fetch(:backup),
        authentication_key: fixture.fetch(:authentication_key)
      )
      assert_equal Digest::SHA256.file(File.join(fixture.fetch(:backup), "manifest.json.age")).hexdigest,
        marker.fetch("manifest_sha256")

      error = assert_raises(Screenote::SelfHosted::BackupSet::Error) do
        Screenote::SelfHosted::BackupSet.authenticate_completion!(
          source: fixture.fetch(:backup),
          authentication_key: fixture.fetch(:wrong_authentication_key)
        )
      end
      assert_equal "completion marker authentication failed", error.message
    end
  end

  test "authenticates the completion marker before invoking age" do
    with_fixture do |fixture|
      _stdout, stderr, status = run_backup(fixture)
      assert status.success?, stderr

      _stdout, stderr, status = run_restore(
        fixture,
        authentication_key: fixture.fetch(:wrong_authentication_key)
      )
      assert_not status.success?
      assert_includes stderr, "backup set is invalid"
      assert_not File.exist?(fixture.fetch(:identity_log))
      assert_empty Dir.children(fixture.fetch(:restored_volume))
      assert_empty Dir.children(fixture.fetch(:operator_destination))

      forge_manifest_without_authentication_key!(fixture)
      _stdout, stderr, status = run_restore(fixture)
      assert_not status.success?
      assert_includes stderr, "backup set is invalid"
      assert_not File.exist?(fixture.fetch(:identity_log))
      assert_empty Dir.children(fixture.fetch(:restored_volume))
      assert_empty Dir.children(fixture.fetch(:operator_destination))
    end
  end

  test "requires a restricted authentication key with bounded length" do
    with_fixture do |fixture|
      hard_link = File.join(fixture.fetch(:root), "hard-linked-backup-authentication-key")
      File.link(fixture.fetch(:authentication_key), hard_link)
      _stdout, stderr, status = run_backup(fixture)
      assert_not status.success?
      assert_includes stderr, "single-link restricted regular file"
      FileUtils.rm_f(hard_link)

      fifo = File.join(fixture.fetch(:root), "fifo-backup-authentication-key")
      File.mkfifo(fifo, 0o400)
      error = Timeout.timeout(2) do
        assert_raises(Screenote::SelfHosted::BackupSet::Error) do
          Screenote::SelfHosted::BackupSet.read_authentication_key(fifo)
        end
      end
      assert_includes error.message, "single-link restricted regular file"

      File.chmod(0o644, fixture.fetch(:authentication_key))
      _stdout, stderr, status = run_backup(fixture)
      assert_not status.success?
      assert_includes stderr, "restricted regular file"

      File.chmod(0o600, fixture.fetch(:authentication_key))
      File.binwrite(fixture.fetch(:authentication_key), "k" * 31)
      File.chmod(0o400, fixture.fetch(:authentication_key))
      _stdout, stderr, status = run_backup(fixture)
      assert_not status.success?
      assert_includes stderr, "32 to 4096 bytes"

      File.chmod(0o600, fixture.fetch(:authentication_key))
      File.binwrite(fixture.fetch(:authentication_key), "k" * 4097)
      File.chmod(0o400, fixture.fetch(:authentication_key))
      _stdout, stderr, status = run_backup(fixture)
      assert_not status.success?
      assert_includes stderr, "32 to 4096 bytes"
    end
  end

  test "encrypts manifest bytes larger than pipe capacity without deadlocking" do
    with_fixture do |fixture|
      creator = backup_creator(fixture)
      manifest_bytes = JSON.generate("padding" => "m" * (256 * 1024))
      output = File.join(fixture.fetch(:root), "large-manifest.json.age")

      Timeout.timeout(5) { creator.send(:encrypt_bytes, manifest_bytes, output) }

      _magic, _recipient, _digest, decrypted = File.binread(output).split("\n", 4)
      assert_equal manifest_bytes, decrypted
    end
  end

  test "rejects an oversized manifest before finalizing the backup set" do
    with_fixture do |fixture|
      FileUtils.mkdir_p(File.dirname(fixture.fetch(:backup)), mode: 0o700)
      creator = backup_creator(fixture)
      oversized_manifest = { "padding" => "m" * Screenote::SelfHosted::BackupSet::MAX_JSON_BYTES }
      creator.define_singleton_method(:build_manifest) { |_inspection, _artifacts| oversized_manifest }

      error = assert_raises(Screenote::SelfHosted::BackupSet::Error) { creator.call }

      assert_equal "manifest is too large", error.message
      assert_not File.exist?(fixture.fetch(:backup))
      assert_empty Dir.children(File.dirname(fixture.fetch(:backup)))
    end
  end

  test "rejects tampering and wrong image or identity without mutating either restore target" do
    with_fixture do |fixture|
      _stdout, stderr, status = run_backup(fixture)
      assert status.success?, stderr

      volume_archive = File.join(fixture.fetch(:backup), "volume.tar.age")
      bytes = File.binread(volume_archive)
      bytes.setbyte(bytes.bytesize - 1, bytes.getbyte(bytes.bytesize - 1) ^ 0xff)
      File.binwrite(volume_archive, bytes)

      _stdout, stderr, status = run_restore(fixture)
      assert_not status.success?
      assert_includes stderr, "backup set is invalid"
      assert_empty Dir.children(fixture.fetch(:restored_volume))
      assert_empty Dir.children(fixture.fetch(:operator_destination))

      FileUtils.rm_rf(fixture.fetch(:backup))
      _stdout, stderr, status = run_backup(fixture)
      assert status.success?, stderr

      _stdout, stderr, status = run_restore(
        fixture,
        image: "ghcr.io/future-spin/screenote@sha256:#{'b' * 64}"
      )
      assert_not status.success?
      assert_includes stderr, "restore image does not match"
      assert_empty Dir.children(fixture.fetch(:restored_volume))
      assert_empty Dir.children(fixture.fetch(:operator_destination))

      File.chmod(0o600, fixture.fetch(:identity))
      File.binwrite(fixture.fetch(:identity), "AGE-SECRET-KEY-WRONG\n")
      File.chmod(0o400, fixture.fetch(:identity))
      _stdout, stderr, status = run_restore(fixture)
      assert_not status.success?
      assert_includes stderr, "backup set is invalid"
      assert_empty Dir.children(fixture.fetch(:restored_volume))
      assert_empty Dir.children(fixture.fetch(:operator_destination))
    end
  end

  test "requires an empty explicit target and never removes existing data" do
    with_fixture do |fixture|
      _stdout, stderr, status = run_backup(fixture)
      assert status.success?, stderr

      sentinel = File.join(fixture.fetch(:restored_volume), "keep-me")
      File.binwrite(sentinel, "untouched")

      _stdout, stderr, status = run_restore(fixture)

      assert_not status.success?
      assert_includes stderr, "restore volume must be empty"
      assert_equal "untouched", File.binread(sentinel)
      assert_empty Dir.children(fixture.fetch(:operator_destination))
    end
  end

  test "rejects plaintext output, raw secrets in configuration, and symlinks" do
    with_fixture do |fixture|
      File.open(fixture.fetch(:configuration), "a") do |file|
        file.puts "SECRET_KEY_BASE=#{fixture.fetch(:secret)}"
      end

      _stdout, stderr, status = run_backup(fixture)
      assert_not status.success?
      assert_includes stderr, "configuration contains a raw secret assignment"
      assert_not File.exist?(fixture.fetch(:backup))
      assert_not_includes stderr, fixture.fetch(:secret)

      File.binwrite(fixture.fetch(:configuration), fixture.fetch(:configuration_bytes))
      File.symlink("secret_key_base", File.join(fixture.fetch(:secrets), "linked-secret"))

      _stdout, stderr, status = run_backup(fixture)
      assert_not status.success?
      assert_includes stderr, "secret bundle must not contain symlinks"
      assert_not File.exist?(fixture.fetch(:backup))
    end
  end

  test "requires finalized age-encrypted S3 evidence matching every database blob" do
    with_fixture(storage: "self_hosted_s3") do |fixture|
      _stdout, stderr, status = run_backup(fixture)
      assert_not status.success?
      assert_includes stderr, "S3 backup evidence is required"

      objects = [
        {
          "service" => "self_hosted_s3",
          "key" => fixture.fetch(:blob_key),
          "byte_size" => fixture.fetch(:blob_bytes).bytesize,
          "checksum" => Base64.strict_encode64(Digest::MD5.digest(fixture.fetch(:blob_bytes))),
          "version" => "opaque-provider-version-1"
        }
      ]
      completed_at = Time.now.utc
      evidence = {
        "schema" => "screenote-s3-snapshot-evidence/v1",
        "status" => "finalized",
        "namespace_fingerprint" => fixture.fetch(:namespace_fingerprint),
        "snapshot_reference" => "provider-copy-opaque-123",
        "backup_quiesced_at" => (completed_at - 2.minutes).iso8601,
        "snapshot_started_at" => (completed_at - 1.minute).iso8601,
        "snapshot_completed_at" => completed_at.iso8601,
        "object_set_encryption" => {
          "scheme" => "age",
          "recipient_fingerprint" => Digest::SHA256.hexdigest(RECIPIENT),
          "authenticated" => true
        },
        "object_set_sha256" => Digest::SHA256.hexdigest(JSON.generate(objects)),
        "objects" => objects
      }
      File.binwrite(fixture.fetch(:s3_evidence), JSON.generate(evidence))
      File.chmod(0o600, fixture.fetch(:s3_evidence))

      _stdout, stderr, status = run_backup(fixture, s3_evidence: fixture.fetch(:s3_evidence))

      assert status.success?, stderr
      assert File.file?(File.join(fixture.fetch(:backup), "s3-evidence.age"))

      _stdout, stderr, status = run_restore(fixture)
      assert status.success?, stderr
    end
  end

  private

  def with_fixture(storage: "self_hosted_local")
    Dir.mktmpdir("screenote-backup-restore") do |root|
      storage_root = File.join(root, "volume")
      restored_volume = File.join(root, "restored-volume")
      operator_destination = File.join(root, "restored-operator")
      secrets = File.join(root, "secrets")
      [ storage_root, restored_volume, operator_destination, secrets ].each do |directory|
        FileUtils.mkdir_p(directory, mode: 0o700)
      end

      configuration = File.join(root, ".env")
      configuration_bytes = <<~ENV
        SCREENOTE_IMAGE=#{IMAGE}
        SCREENOTE_BASE_URL=http://screenote.internal:3005
        SCREENOTE_SECRET_KEY_BASE_PATH=./secrets/secret_key_base
      ENV
      File.binwrite(configuration, configuration_bytes)
      File.chmod(0o600, configuration)

      secret = "not-printed-#{'s' * 48}"
      File.binwrite(File.join(secrets, "secret_key_base"), secret)
      File.chmod(0o400, File.join(secrets, "secret_key_base"))
      File.binwrite(File.join(storage_root, "state.txt"), "primary-state")

      blob_key = "aa11-screenote-blob"
      blob_bytes = "screenote-private-blob"
      namespace_fingerprint = "f" * 64
      write_database_set(
        storage_root,
        storage:,
        namespace_fingerprint:,
        blob_key:,
        blob_bytes:
      )

      if storage == "self_hosted_local"
        blob_path = File.join(storage_root, "blobs", blob_key.first(2), blob_key.first(4).last(2), blob_key)
        FileUtils.mkdir_p(File.dirname(blob_path), mode: 0o700)
        File.binwrite(blob_path, blob_bytes)
      end

      age = File.join(root, "age")
      write_fake_age(age)
      identity = File.join(root, "age-identity")
      File.binwrite(identity, "AGE-SECRET-KEY-TEST\n")
      File.chmod(0o400, identity)
      authentication_key = File.join(root, "backup-authentication-key")
      File.binwrite(authentication_key, "screenote-backup-authentication-#{'k' * 48}")
      File.chmod(0o400, authentication_key)
      wrong_authentication_key = File.join(root, "wrong-backup-authentication-key")
      File.binwrite(wrong_authentication_key, "screenote-wrong-backup-authentication-#{'w' * 48}")
      File.chmod(0o400, wrong_authentication_key)
      compose_contract = File.join(root, "compose-contract.json")
      File.binwrite(
        compose_contract,
        JSON.generate(
          "schema" => "screenote-compose-contract/v1",
          "files" => [ { "name" => "compose.yaml", "sha256" => "d" * 64 } ]
        )
      )
      File.chmod(0o600, compose_contract)

      yield(
        root:,
        storage_root:,
        restored_volume:,
        operator_destination:,
        configuration:,
        configuration_bytes:,
        secrets:,
        secret:,
        age:,
        identity:,
        identity_log: File.join(root, "age-identity-paths.log"),
        authentication_key:,
        wrong_authentication_key:,
        backup: File.join(root, "external", "backup.screenote"),
        compose_contract:,
        s3_evidence: File.join(root, "s3-evidence.json"),
        namespace_fingerprint:,
        blob_key:,
        blob_bytes:
      )
    end
  end

  def write_database_set(root, storage:, namespace_fingerprint:, blob_key:, blob_bytes:)
    %w[primary cache queue cable].each do |role|
      database = SQLite3::Database.new(File.join(root, "#{role}.sqlite3"))
      database.execute("PRAGMA foreign_keys = ON")
      database.execute("CREATE TABLE schema_migrations (version varchar NOT NULL PRIMARY KEY)")
      schema_version = role == "primary" ? "20260805134000" : "1"
      database.execute("INSERT INTO schema_migrations(version) VALUES (?)", schema_version)

      next unless role == "primary"

      database.execute(<<~SQL)
        CREATE TABLE installations (
          singleton_key varchar NOT NULL,
          deployment_mode varchar NOT NULL,
          storage_service varchar NOT NULL,
          storage_namespace_fingerprint varchar NOT NULL
        )
      SQL
      database.execute(
        "INSERT INTO installations VALUES (?, ?, ?, ?)",
        [ "screenote", "self_hosted", storage, namespace_fingerprint ]
      )
      database.execute(<<~SQL)
        CREATE TABLE active_storage_blobs (
          id integer PRIMARY KEY,
          service_name varchar NOT NULL,
          key varchar NOT NULL,
          byte_size integer NOT NULL,
          checksum varchar
        )
      SQL
      database.execute(
        "INSERT INTO active_storage_blobs(service_name, key, byte_size, checksum) VALUES (?, ?, ?, ?)",
        [ storage, blob_key, blob_bytes.bytesize, Base64.strict_encode64(Digest::MD5.digest(blob_bytes)) ]
      )
    ensure
      database&.close
    end
  end

  def write_fake_age(path)
    File.binwrite(path, <<~'RUBY')
      #!/usr/bin/env ruby
      require "digest"

      if ARGV.include?("--encrypt")
        recipient_file = ARGV.fetch(ARGV.index("--recipients-file") + 1)
        recipient = File.read(recipient_file).strip
        body = STDIN.binmode.read
        STDOUT.binmode.write("SCREENOTE-FAKE-AGE\n#{recipient}\n#{Digest::SHA256.hexdigest(body)}\n#{body}")
        exit 0
      end

      if ARGV.include?("--decrypt")
        identity = ARGV.fetch(ARGV.index("--identity") + 1)
        input = ARGV.last
        if (identity_log = ENV["SCREENOTE_FAKE_AGE_IDENTITY_LOG"])
          File.open(identity_log, File::WRONLY | File::CREAT | File::APPEND, 0o600) do |file|
            file.puts(identity)
          end
        end
        exit 1 unless File.binread(identity) == "AGE-SECRET-KEY-TEST\n"
        magic, recipient, digest, body = File.binread(input).split("\n", 4)
        exit 1 unless magic == "SCREENOTE-FAKE-AGE" && recipient == "age1screenotetest"
        exit 1 unless Digest::SHA256.hexdigest(body) == digest
        STDOUT.binmode.write(body)
        exit 0
      end

      exit 2
    RUBY
    File.chmod(0o700, path)
  end

  def backup_creator(fixture)
    Screenote::SelfHosted::BackupSet::Creator.new(
      storage_root: fixture.fetch(:storage_root),
      destination: fixture.fetch(:backup),
      recipient: RECIPIENT,
      configuration: fixture.fetch(:configuration),
      secret_bundle: fixture.fetch(:secrets),
      compose_contract: fixture.fetch(:compose_contract),
      authentication_key: fixture.fetch(:authentication_key),
      image: IMAGE,
      predecessor: "none",
      age: fixture.fetch(:age)
    )
  end

  def run_backup(fixture, s3_evidence: nil, authentication_key: fixture.fetch(:authentication_key))
    FileUtils.mkdir_p(File.dirname(fixture.fetch(:backup)), mode: 0o700)
    arguments = [
      BACKUP,
      "--storage-root", fixture.fetch(:storage_root),
      "--destination", fixture.fetch(:backup),
      "--recipient", RECIPIENT,
      "--configuration", fixture.fetch(:configuration),
      "--secret-bundle", fixture.fetch(:secrets),
      "--compose-contract", fixture.fetch(:compose_contract),
      "--authentication-key", authentication_key,
      "--image", IMAGE,
      "--predecessor", "none"
    ]
    arguments.concat([ "--s3-evidence", s3_evidence ]) if s3_evidence
    Open3.capture3(
      { "SCREENOTE_AGE_BIN" => fixture.fetch(:age) },
      *arguments,
      chdir: Rails.root.to_s
    )
  end

  def run_restore(fixture, image: IMAGE, authentication_key: fixture.fetch(:authentication_key))
    FileUtils.rm_f(fixture.fetch(:identity_log))
    Open3.capture3(
      {
        "SCREENOTE_AGE_BIN" => fixture.fetch(:age),
        "SCREENOTE_FAKE_AGE_IDENTITY_LOG" => fixture.fetch(:identity_log)
      },
      RESTORE,
      "--source", fixture.fetch(:backup),
      "--identity", fixture.fetch(:identity),
      "--storage-root", fixture.fetch(:restored_volume),
      "--operator-destination", fixture.fetch(:operator_destination),
      "--compose-contract", fixture.fetch(:compose_contract),
      "--authentication-key", authentication_key,
      "--image", image,
      "--predecessor", "none",
      chdir: Rails.root.to_s
    )
  end

  def forge_manifest_without_authentication_key!(fixture)
    manifest_path = File.join(fixture.fetch(:backup), "manifest.json.age")
    _magic, _recipient, _digest, body = File.binread(manifest_path).split("\n", 4)
    manifest = JSON.parse(body)
    manifest["created_at"] = "2099-01-01T00:00:00Z"

    recipient_file = File.join(fixture.fetch(:root), "attacker-public-recipient")
    File.binwrite(recipient_file, "#{RECIPIENT}\n")
    ciphertext, error, status = Open3.capture3(
      fixture.fetch(:age),
      "--encrypt",
      "--recipients-file",
      recipient_file,
      stdin_data: JSON.generate(manifest)
    )
    raise "fake age re-encryption failed: #{error}" unless status.success?

    File.binwrite(manifest_path, ciphertext)
    File.chmod(0o600, manifest_path)
    marker_path = File.join(fixture.fetch(:backup), "COMPLETE")
    marker = JSON.parse(File.binread(marker_path))
    marker["manifest_sha256"] = Digest::SHA256.hexdigest(ciphertext)
    File.binwrite(marker_path, JSON.generate(marker))
    File.chmod(0o600, marker_path)
  end
end
