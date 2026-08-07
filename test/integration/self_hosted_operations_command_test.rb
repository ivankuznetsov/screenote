# frozen_string_literal: true

# screenote-edition: self_hosted

require "test_helper"
require "digest"
require "fileutils"
require "json"
require "open3"
require "rbconfig"
require "tmpdir"

class SelfHostedOperationsCommandTest < ActiveSupport::TestCase
  BACKUP = Rails.root.join("bin/self-host-backup").to_s.freeze
  RESTORE = Rails.root.join("bin/self-host-restore").to_s.freeze
  DIAGNOSTICS = Rails.root.join("bin/self-host-diagnostics").to_s.freeze
  HOST_IDENTITY_PRELOAD = Rails.root.join("test/support/self_hosted_host_identity").to_s.freeze
  IMAGE = "ghcr.io/future-spin/screenote@sha256:#{'a' * 64}".freeze

  test "backup validates the running immutable image, stops gracefully, archives, then restarts" do
    with_fixture do |fixture|
      stale_image = "ghcr.io/future-spin/screenote@sha256:#{'b' * 64}"
      File.binwrite(
        fixture.fetch(:configuration),
        "SCREENOTE_IMAGE=#{stale_image}\nSCREENOTE_SECRET_KEY_BASE_PATH=./secrets/secret_key_base\n"
      )
      stdout, stderr, status = run_backup(fixture)

      assert status.success?, stderr
      trace = File.readlines(fixture.fetch(:trace), chomp: true)
      assert_operator trace.index("compose stop --timeout 120 screenote"), :<,
        trace.index { |line| line.include?("self_hosted_backup_internal") }
      assert_operator trace.index { |line| line.include?("self_hosted_backup_internal") }, :<,
        trace.index("compose up --detach --no-deps --wait --wait-timeout 120 screenote")
      archive_command = trace.find { |line| line.include?("self_hosted_backup_internal") }
      assert_includes archive_command, "--volume #{File.dirname(fixture.fetch(:backup))}:/screenote-output"
      assert_includes archive_command,
        "--volume #{fixture.fetch(:authentication_key)}:/screenote-input/backup-authentication-key:ro"
      assert_includes archive_command,
        "--authentication-key /screenote-input/backup-authentication-key"
      assert_includes archive_command, "--predecessor none"
      assert_includes stdout, "Backup finalized"
      assert_not_includes stdout, fixture.fetch(:secret)
      assert_not_includes stderr, fixture.fetch(:secret)
    end
  end

  test "backup leaves the service stopped when archive creation fails" do
    with_fixture do |fixture|
      _stdout, stderr, status = run_backup(
        fixture,
        { "SCREENOTE_FAKE_BACKUP_FAILURE" => "true" }
      )

      assert_not status.success?
      assert_equal 75, status.exitstatus
      assert_includes stderr, "remains stopped"
      trace = File.readlines(fixture.fetch(:trace), chomp: true)
      assert_includes trace, "compose stop --timeout 120 screenote"
      assert_not_includes trace, "compose up --detach --no-deps --wait --wait-timeout 120 screenote"
    end
  end

  test "backup reports a stopped service when post-stop validation fails" do
    with_fixture do |fixture|
      _stdout, stderr, status = run_backup(
        fixture,
        { "SCREENOTE_FAKE_UNCLEAN_EXIT" => "true" }
      )

      assert_equal 75, status.exitstatus
      assert_includes stderr, "did not stop gracefully"
      assert_includes stderr, "remains stopped"
      trace = File.readlines(fixture.fetch(:trace), chomp: true)
      assert_includes trace, "compose stop --timeout 120 screenote"
      assert_not_includes trace, "compose up --detach --no-deps --wait --wait-timeout 120 screenote"
    end
  end

  test "backup redacts provider hook output when the S3 snapshot fails" do
    with_fixture do |fixture|
      provider_secret = "provider-error-secret-#{'p' * 48}"
      hook = File.join(fixture.fetch(:root), "s3-snapshot-hook")
      evidence = File.join(fixture.fetch(:output), "s3-evidence.json")
      File.binwrite(hook, <<~SH)
        #!/bin/sh
        printf '%s\\n' '#{provider_secret}'
        printf '%s\\n' '#{provider_secret}' >&2
        exit 42
      SH
      File.chmod(0o700, hook)

      stdout, stderr, status = run_backup(
        fixture,
        s3_snapshot_command: hook,
        s3_evidence: evidence
      )

      assert_equal 75, status.exitstatus
      assert_includes stderr, "S3 snapshot command failed"
      assert_not_includes stdout, provider_secret
      assert_not_includes stderr, provider_secret
      assert_includes File.readlines(fixture.fetch(:trace), chomp: true), "compose stop --timeout 120 screenote"
    end
  end

  test "backup rejects a bundle other than the portable secrets directory before stopping" do
    with_fixture do |fixture|
      wrong_bundle = File.join(fixture.fetch(:root), "wrong-secrets")
      FileUtils.mkdir_p(wrong_bundle, mode: 0o700)
      File.binwrite(File.join(wrong_bundle, "secret_key_base"), fixture.fetch(:secret))
      File.chmod(0o400, File.join(wrong_bundle, "secret_key_base"))

      _stdout, stderr, status = run_backup(fixture, {}, secret_bundle: wrong_bundle)

      assert_equal 73, status.exitstatus
      assert_includes stderr, "portable secrets directory"
      assert_not_includes File.read(fixture.fetch(:trace)), "compose stop"
    end
  end

  test "backup rejects stale files that are not consumed by the effective Compose service" do
    with_fixture do |fixture|
      stale = File.join(fixture.fetch(:secrets), "stale_secret")
      File.binwrite(stale, "stale-#{'x' * 48}")
      File.chmod(0o400, stale)

      _stdout, stderr, status = run_backup(fixture)

      assert_equal 73, status.exitstatus
      assert_includes stderr, "exactly the effective Compose secret files"
      assert_not_includes File.read(fixture.fetch(:trace)), "compose stop"
    end
  end

  test "backup rejects absolute secret paths that would not survive restore relocation" do
    with_fixture do |fixture|
      File.binwrite(
        fixture.fetch(:configuration),
        "SCREENOTE_IMAGE=#{IMAGE}\nSCREENOTE_SECRET_KEY_BASE_PATH=#{fixture.fetch(:secrets)}/secret_key_base\n"
      )

      _stdout, stderr, status = run_backup(fixture)

      assert_equal 73, status.exitstatus
      assert_includes stderr, "portable ./secrets paths"
      assert_not_includes File.read(fixture.fetch(:trace)), "compose stop"
    end
  end

  test "backup rejects a consumed overlay secret omitted from the archive" do
    with_fixture do |fixture|
      overlay = File.join(fixture.fetch(:root), "compose.provider.yaml")
      File.binwrite(overlay, <<~YAML)
        services:
          screenote:
            secrets:
              - source: screenote_provider_secret
                target: screenote_provider_secret
        secrets:
          screenote_provider_secret:
            file: ${SCREENOTE_PROVIDER_SECRET_PATH:?Set provider secret path}
      YAML
      File.open(fixture.fetch(:configuration), "a") do |file|
        file.puts "SCREENOTE_PROVIDER_SECRET_PATH=./secrets/provider_secret"
      end
      missing = File.join(fixture.fetch(:secrets), "provider_secret")

      _stdout, stderr, status = run_backup(
        fixture,
        { "SCREENOTE_FAKE_EXTRA_SECRET_FILE" => missing },
        compose_files: [ fixture.fetch(:compose), overlay ]
      )

      assert_equal 73, status.exitstatus
      assert_includes stderr, "effective Compose secret file is unavailable"
      assert_not_includes File.read(fixture.fetch(:trace)), "compose stop"
    end
  end

  test "backup excludes ambient Compose interpolation overrides" do
    with_fixture do |fixture|
      stdout, stderr, status = run_backup(
        fixture,
        {
          "SCREENOTE_FAKE_REJECT_AMBIENT_SECRET_PATH" => "true",
          "SCREENOTE_SECRET_KEY_BASE_PATH" => "/tmp/ambient-secret-must-not-win"
        }
      )

      assert status.success?, stderr
      assert_includes stdout, "Backup finalized"
    end
  end

  test "backup rejects a running container mounted from different secret files" do
    with_fixture do |fixture|
      running_secret = File.join(fixture.fetch(:root), "ambient-running-secret")
      File.binwrite(running_secret, "different-#{'r' * 48}")
      File.chmod(0o400, running_secret)

      _stdout, stderr, status = run_backup(
        fixture,
        { "SCREENOTE_FAKE_RUNNING_SECRET_FILE" => running_secret }
      )

      assert_equal 73, status.exitstatus
      assert_includes stderr, "running Screenote secret mounts do not match"
      assert_not_includes File.read(fixture.fetch(:trace)), "compose stop"
    end
  end

  test "backup rejects a running container mounted from a different storage volume" do
    with_fixture do |fixture|
      _stdout, stderr, status = run_backup(
        fixture,
        { "SCREENOTE_FAKE_RUNNING_STORAGE_VOLUME" => "screenote-ops-test_stale_storage" }
      )

      assert_equal 73, status.exitstatus
      assert_includes stderr, "running Screenote storage volume does not match"
      assert_not_includes File.read(fixture.fetch(:trace)), "compose stop"
    end
  end

  test "backup rejects an authentication key stored inside the running data volume" do
    with_fixture do |fixture|
      _stdout, stderr, status = run_backup(
        fixture,
        { "SCREENOTE_FAKE_RUNNING_STORAGE_SOURCE" => fixture.fetch(:root) }
      )

      assert_equal 73, status.exitstatus
      assert_includes stderr, "authentication key must be outside the running storage volume"
      assert_not_includes File.read(fixture.fetch(:trace)), "compose stop"
    end
  end

  test "backup rejects a public Compose input reused as the authentication key" do
    with_fixture do |fixture|
      File.chmod(0o400, fixture.fetch(:compose))

      _stdout, stderr, status = run_backup(
        fixture.merge(authentication_key: fixture.fetch(:compose))
      )

      assert_equal 73, status.exitstatus
      assert_includes stderr, "dedicated operator file"
      assert_not_includes File.read(fixture.fetch(:trace)), "compose stop"
    end
  end

  test "backup rejects an authentication key copied from an archived application secret" do
    with_fixture do |fixture|
      File.chmod(0o600, fixture.fetch(:authentication_key))
      FileUtils.cp(File.join(fixture.fetch(:secrets), "secret_key_base"), fixture.fetch(:authentication_key))
      File.chmod(0o400, fixture.fetch(:authentication_key))

      _stdout, stderr, status = run_backup(fixture)

      assert_equal 73, status.exitstatus
      assert_includes stderr, "must not duplicate archived or recovery input"
      assert_not_includes File.read(fixture.fetch(:trace)), "compose stop"
    end
  end

  test "restore uses an explicit target volume, verifies in the recorded image, and starts only after verification" do
    with_fixture do |fixture|
      FileUtils.mkdir_p(fixture.fetch(:backup), mode: 0o700)
      stdout, stderr, status = run_restore(fixture)

      assert status.success?, stderr
      trace = File.readlines(fixture.fetch(:trace), chomp: true)
      restore = trace.find { |line| line.include?("self_hosted_restore_internal") }
      verify = trace.find { |line| line.include?("script/self_hosted_restore_verify") }
      start = "compose up --detach --no-deps --wait --wait-timeout 120 screenote"
      assert_includes restore,
        "--mount type=volume,src=#{fixture.fetch(:target_volume)},dst=/rails/storage,volume-nocopy"
      assert_includes restore,
        "--volume #{fixture.fetch(:authentication_key)}:/screenote-input/backup-authentication-key:ro"
      assert_includes restore,
        "--authentication-key /screenote-input/backup-authentication-key"
      assert trace.any? { |line| line.include?("/bin/chown") && line.include?("1000:1000 /rails/storage") }
      assert trace.any? { |line| line.include?("/bin/stat") && line.include?("%u:%g:%a /rails/storage") }
      assert_operator trace.index(restore), :<, trace.index(verify)
      assert_operator trace.index(verify), :<, trace.index(start)
      assert_includes stdout, "Restore verified and started"
      assert_not_includes stdout, fixture.fetch(:secret)
    end
  end

  test "restore refuses a nonempty explicit target before running a container" do
    with_fixture do |fixture|
      FileUtils.mkdir_p(fixture.fetch(:backup), mode: 0o700)
      _stdout, stderr, status = run_restore(
        fixture,
        { "SCREENOTE_FAKE_VOLUME_NONEMPTY" => "true" }
      )

      assert_not status.success?
      assert_equal 73, status.exitstatus
      assert_includes stderr, "target volume must be empty"
      trace = File.readlines(fixture.fetch(:trace), chomp: true)
      assert_not trace.any? { |line| line.include?("self_hosted_restore_internal") }
      assert_not_includes trace, "compose stop --timeout 120 screenote"
    end
  end

  test "restore revalidates portable secret mapping before verifier or startup" do
    with_fixture do |fixture|
      FileUtils.mkdir_p(fixture.fetch(:backup), mode: 0o700)
      _stdout, stderr, status = run_restore(
        fixture,
        { "SCREENOTE_FAKE_RESTORED_SECRET_PATH" => "/tmp/nonportable-restored-secret" }
      )

      assert_equal 73, status.exitstatus
      assert_includes stderr, "portable ./secrets paths"
      trace = File.readlines(fixture.fetch(:trace), chomp: true)
      assert_not trace.any? { |line| line.include?("script/self_hosted_restore_verify") }
      assert_not trace.any? { |line| line.start_with?("compose up") }
    end
  end

  test "restore rejects a wrong authentication key before Docker mutation or service stop" do
    with_fixture do |fixture|
      _stdout, stderr, status = run_restore(
        fixture,
        {},
        authentication_key: fixture.fetch(:wrong_authentication_key)
      )

      assert_equal 65, status.exitstatus
      assert_includes stderr, "backup set authentication failed"
      trace = File.readlines(fixture.fetch(:trace), chomp: true)
      assert_not trace.any? { |line| line.start_with?("volume inspect") || line.start_with?("volume create") }
      assert_not trace.any? { |line| line.start_with?("compose ps") || line.start_with?("compose stop") }
    end
  end

  test "restore rejects an authentication key copied from the age identity" do
    with_fixture do |fixture|
      File.chmod(0o600, fixture.fetch(:authentication_key))
      FileUtils.cp(fixture.fetch(:identity), fixture.fetch(:authentication_key))
      File.chmod(0o400, fixture.fetch(:authentication_key))

      _stdout, stderr, status = run_restore(fixture)

      assert_equal 73, status.exitstatus
      assert_includes stderr, "must not duplicate archived or recovery input"
      trace = File.readlines(fixture.fetch(:trace), chomp: true)
      assert_not trace.any? { |line| line.start_with?("volume inspect") || line.start_with?("compose stop") }
    end
  end

  test "diagnostics execute locally inside the running service without echoing configuration" do
    with_fixture do |fixture|
      stdout, stderr, status = Open3.capture3(
        command_environment(fixture),
        *supported_identity_command(DIAGNOSTICS),
        "--compose-file", fixture.fetch(:compose),
        "--project-name", "screenote-ops-test"
      )

      assert status.success?, stderr
      assert_includes stdout, '"status":"ok"'
      assert_includes File.read(fixture.fetch(:trace)),
        "compose exec -T screenote /rails/bin/docker-entrypoint ./bin/rails runner script/self_hosted_diagnostics"
      assert_not_includes stdout, fixture.fetch(:secret)
      assert_not_includes stderr, fixture.fetch(:secret)
    end
  end

  test "production host identity remains exactly uid and gid 1000" do
    assert_equal 1000, Screenote::SelfHosted::HostOperations::SUPPORTED_UID
    assert_equal 1000, Screenote::SelfHosted::HostOperations::SUPPORTED_GID
  end

  test "operations reject an unsupported user before invoking Docker" do
    command = Screenote::SelfHosted::HostOperations::BackupCommand.new({}, host_uid: 1001, host_gid: 1000)

    _stdout, stderr = capture_io { assert_equal 78, command.call }

    assert_includes stderr, "must run as host uid/gid 1000"
  end

  test "operations reject a mismatched group before invoking Docker" do
    command = Screenote::SelfHosted::HostOperations::BackupCommand.new({}, host_uid: 1000, host_gid: 1001)

    _stdout, stderr = capture_io { assert_equal 78, command.call }

    assert_includes stderr, "must run as host uid/gid 1000"
  end

  test "executable identity preload refuses non-test environments" do
    _stdout, stderr, status = Open3.capture3(
      { "RAILS_ENV" => "production" },
      RbConfig.ruby,
      "-rbundler/setup",
      "-r#{HOST_IDENTITY_PRELOAD}",
      "-e",
      "exit 0"
    )

    assert_not status.success?
    assert_includes stderr, "self-hosted identity preload is test-only"
  end

  private

  def with_fixture
    Dir.mktmpdir("screenote-operations") do |root|
      compose = File.join(root, "compose.yaml")
      configuration = File.join(root, ".env")
      secrets = File.join(root, "secrets")
      output = File.join(root, "external")
      operator = File.join(root, "operator")
      identity = File.join(root, "age-identity")
      authentication_key = File.join(root, "backup-authentication-key")
      wrong_authentication_key = File.join(root, "wrong-backup-authentication-key")
      target_volume = "screenote_restore_#{Process.pid}"
      secret = "must-not-print-#{'s' * 48}"
      [ secrets, output, operator ].each { |directory| FileUtils.mkdir_p(directory, mode: 0o700) }
      File.binwrite(compose, <<~YAML)
        services:
          screenote:
            secrets:
              - source: screenote_secret_key_base
                target: screenote_secret_key_base
        secrets:
          screenote_secret_key_base:
            file: ${SCREENOTE_SECRET_KEY_BASE_PATH:?Set application secret path}
      YAML
      File.binwrite(configuration, "SCREENOTE_IMAGE=#{IMAGE}\nSCREENOTE_SECRET_KEY_BASE_PATH=./secrets/secret_key_base\n")
      File.chmod(0o600, configuration)
      File.binwrite(File.join(secrets, "secret_key_base"), secret)
      File.chmod(0o400, File.join(secrets, "secret_key_base"))
      File.binwrite(identity, "AGE-SECRET-KEY-TEST-#{'i' * 48}\n")
      File.chmod(0o400, identity)
      File.binwrite(authentication_key, "operator-authentication-key-#{'k' * 48}")
      File.chmod(0o400, authentication_key)
      File.binwrite(wrong_authentication_key, "wrong-operator-authentication-key-#{'w' * 48}")
      File.chmod(0o400, wrong_authentication_key)

      docker = File.join(root, "docker")
      trace = File.join(root, "docker.trace")
      state = File.join(root, "state")
      File.binwrite(state, "running")
      write_fake_docker(docker)

      yield(
        root:,
        compose:,
        configuration:,
        secrets:,
        secret:,
        output:,
        operator:,
        identity:,
        authentication_key:,
        wrong_authentication_key:,
        docker:,
        trace:,
        state:,
        target_volume:,
        backup: File.join(output, "backup.screenote")
      )
    end
  end

  def run_backup(fixture, extra_environment = {}, secret_bundle: fixture.fetch(:secrets),
    compose_files: [ fixture.fetch(:compose) ], s3_snapshot_command: nil, s3_evidence: nil)
    compose_arguments = compose_files.flat_map { |file| [ "--compose-file", file ] }
    arguments = [
      *supported_identity_command(BACKUP),
      "--destination", fixture.fetch(:backup),
      "--recipient", "age1screenotetest",
      "--authentication-key", fixture.fetch(:authentication_key),
      "--configuration", fixture.fetch(:configuration),
      "--secret-bundle", secret_bundle,
      "--image", IMAGE,
      "--predecessor", "none",
      *compose_arguments,
      "--project-name", "screenote-ops-test"
    ]
    arguments.concat([ "--s3-snapshot-command", s3_snapshot_command, "--s3-evidence", s3_evidence ]) if
      s3_snapshot_command || s3_evidence
    Open3.capture3(
      command_environment(fixture).merge(
        "SCREENOTE_FAKE_CONFIGURATION" => fixture.fetch(:configuration),
        "SCREENOTE_FAKE_REQUIRE_PINNED_COMPOSE" => "true"
      ).merge(extra_environment),
      *arguments
    )
  end

  def run_restore(fixture, extra_environment = {}, authentication_key: fixture.fetch(:authentication_key))
    prepare_authenticated_backup(fixture)
    Open3.capture3(
      command_environment(fixture).merge(extra_environment),
      *supported_identity_command(RESTORE),
      "--source", fixture.fetch(:backup),
      "--identity", fixture.fetch(:identity),
      "--authentication-key", authentication_key,
      "--target-volume", fixture.fetch(:target_volume),
      "--operator-destination", fixture.fetch(:operator),
      "--image", IMAGE,
      "--predecessor", "none",
      "--compose-file", fixture.fetch(:compose),
      "--project-name", "screenote-ops-test"
    )
  end


  def prepare_authenticated_backup(fixture)
    source = fixture.fetch(:backup)
    FileUtils.mkdir_p(source, mode: 0o700)
    manifest = File.join(source, "manifest.json.age")
    File.binwrite(manifest, "screenote-operations-encrypted-manifest")
    File.chmod(0o600, manifest)
    key = File.binread(fixture.fetch(:authentication_key))
    fingerprint = Screenote::SelfHosted::BackupSet.authentication_key_fingerprint(key)
    manifest_sha256 = Digest::SHA256.file(manifest).hexdigest
    marker = {
      "schema" => Screenote::SelfHosted::BackupSet::COMPLETE_SCHEMA,
      "manifest_sha256" => manifest_sha256,
      "authentication_key_fingerprint" => fingerprint,
      "authentication_hmac_sha256" => Screenote::SelfHosted::BackupSet.completion_authentication_hmac(
        key,
        manifest_sha256,
        fingerprint
      )
    }
    complete = File.join(source, "COMPLETE")
    File.binwrite(complete, JSON.generate(marker))
    File.chmod(0o600, complete)
  ensure
    key&.clear
  end

  def command_environment(fixture)
    {
      "RAILS_ENV" => "test",
      "SCREENOTE_DOCKER_BIN" => fixture.fetch(:docker),
      "SCREENOTE_FAKE_TRACE" => fixture.fetch(:trace),
      "SCREENOTE_FAKE_STATE" => fixture.fetch(:state),
      "SCREENOTE_FAKE_IMAGE" => IMAGE,
      "SCREENOTE_FAKE_SECRET_FILE" => File.join(fixture.fetch(:secrets), "secret_key_base"),
      "SCREENOTE_FAKE_OPERATOR" => fixture.fetch(:operator)
    }
  end

  def supported_identity_command(executable)
    [ RbConfig.ruby, "-rbundler/setup", "-r#{HOST_IDENTITY_PRELOAD}", executable ]
  end

  def write_fake_docker(path)
    File.binwrite(path, <<~'RUBY')
      #!/usr/bin/env ruby
      require "fileutils"
      require "json"

      arguments = ARGV.dup
      arguments.shift while arguments.first == "--log-level" && arguments.shift && arguments.shift
      compose_index = arguments.index("compose")
      command = compose_index ? arguments[(compose_index + 1)..] : arguments
      if compose_index && arguments.last != "version" && ENV["SCREENOTE_FAKE_REQUIRE_PINNED_COMPOSE"] == "true"
        configuration = ENV.fetch("SCREENOTE_FAKE_CONFIGURATION")
        project_directory = File.dirname(configuration)
        pinned = arguments.each_cons(2).include?([ "--env-file", configuration ]) &&
          arguments.each_cons(2).include?([ "--project-directory", project_directory ]) &&
          ENV["SCREENOTE_IMAGE"] == ENV.fetch("SCREENOTE_FAKE_IMAGE")
        abort "backup Compose invocation was not pinned" unless pinned
      end
      while command.first == "--file" || command.first == "--project-name" || command.first == "--project-directory" || command.first == "--env-file"
        command.shift(2)
      end
      File.open(ENV.fetch("SCREENOTE_FAKE_TRACE"), "a") { |file| file.puts(([ compose_index ? "compose" : nil, *command ].compact).join(" ")) }

      if compose_index && command == [ "version" ]
        exit 0
      elsif compose_index && command == [ "config", "--format", "json" ]
        if ENV["SCREENOTE_FAKE_REJECT_AMBIENT_SECRET_PATH"] == "true" && ENV.key?("SCREENOTE_SECRET_KEY_BASE_PATH")
          abort "ambient Compose secret override leaked into the sanitized environment"
        end
        project_directory_index = arguments.index("--project-directory")
        secret_file = if project_directory_index
          File.join(arguments.fetch(project_directory_index + 1), "secrets", "secret_key_base")
        else
          ENV.fetch("SCREENOTE_FAKE_SECRET_FILE")
        end
        definitions = {
          "screenote_secret_key_base" => {
            "name" => "screenote-ops-test_screenote_secret_key_base",
            "file" => secret_file
          }
        }
        consumed = [{ "source" => "screenote_secret_key_base", "target" => "screenote_secret_key_base" }]
        if ENV["SCREENOTE_FAKE_EXTRA_SECRET_FILE"]
          definitions["screenote_provider_secret"] = {
            "name" => "screenote-ops-test_screenote_provider_secret",
            "file" => ENV.fetch("SCREENOTE_FAKE_EXTRA_SECRET_FILE")
          }
          consumed << { "source" => "screenote_provider_secret", "target" => "screenote_provider_secret" }
        end
        puts JSON.generate(
          "services" => {
            "screenote" => {
              "secrets" => consumed,
              "volumes" => [
                {
                  "type" => "volume",
                  "source" => "screenote_storage",
                  "target" => "/rails/storage",
                  "volume" => {}
                }
              ]
            }
          },
          "secrets" => definitions,
          "volumes" => {
            "screenote_storage" => { "name" => "screenote-ops-test_screenote_storage" }
          }
        )
      elsif compose_index && command == [ "ps", "--quiet", "screenote" ]
        puts "screenote-container" if File.read(ENV.fetch("SCREENOTE_FAKE_STATE")).strip == "running"
      elsif arguments.first == "inspect" && arguments.include?("{{.Config.Image}}")
        puts ENV.fetch("SCREENOTE_FAKE_IMAGE")
      elsif arguments.first == "inspect" && arguments.include?("{{json .Mounts}}")
        storage_name = ENV.fetch("SCREENOTE_FAKE_RUNNING_STORAGE_VOLUME", "screenote-ops-test_screenote_storage")
        storage_source = ENV.fetch(
          "SCREENOTE_FAKE_RUNNING_STORAGE_SOURCE",
          "/var/lib/docker/volumes/#{storage_name}/_data"
        )
        puts JSON.generate([
          {
            "Type" => "bind",
            "Source" => ENV.fetch("SCREENOTE_FAKE_RUNNING_SECRET_FILE", ENV.fetch("SCREENOTE_FAKE_SECRET_FILE")),
            "Destination" => "/run/secrets/screenote_secret_key_base",
            "Mode" => "ro",
            "RW" => false
          },
          {
            "Type" => "volume",
            "Name" => storage_name,
            "Source" => storage_source,
            "Destination" => "/rails/storage",
            "Driver" => "local",
            "Mode" => "rw",
            "RW" => true
          }
        ])
      elsif arguments.first == "inspect" && arguments.any? { |value| value.include?("State.Status") }
        state = File.read(ENV.fetch("SCREENOTE_FAKE_STATE")).strip
        if state == "running"
          puts "running|healthy|0|false|"
        elsif ENV["SCREENOTE_FAKE_UNCLEAN_EXIT"] == "true"
          puts "exited|none|137|true|"
        else
          puts "exited|none|143|false|"
        end
      elsif compose_index && command.first(2) == [ "stop", "--timeout" ]
        File.binwrite(ENV.fetch("SCREENOTE_FAKE_STATE"), "exited")
      elsif compose_index && command.any? { |value| value.include?("self_hosted_backup_internal") }
        exit 75 if ENV["SCREENOTE_FAKE_BACKUP_FAILURE"] == "true"
      elsif arguments.first(2) == [ "volume", "inspect" ] && arguments.include?("{{json .}}")
        name = arguments.last
        mountpoint = ENV.fetch(
          "SCREENOTE_FAKE_RUNNING_STORAGE_SOURCE",
          "/var/lib/docker/volumes/#{name}/_data"
        )
        puts JSON.generate(
          "Name" => name,
          "Driver" => "local",
          "Mountpoint" => mountpoint
        )
      elsif arguments.first(2) == [ "volume", "inspect" ]
        exit 0
      elsif arguments.first(2) == [ "volume", "create" ]
        puts arguments.last
      elsif arguments.first == "run" && arguments.include?("/usr/bin/find")
        puts "occupied" if ENV["SCREENOTE_FAKE_VOLUME_NONEMPTY"] == "true"
      elsif arguments.first == "run" && arguments.include?("/bin/stat")
        puts "1000:1000:700"
      elsif arguments.first == "run" && arguments.any? { |value| value.include?("self_hosted_restore_internal") }
        operator = ENV.fetch("SCREENOTE_FAKE_OPERATOR")
        File.binwrite(
          File.join(operator, ".env"),
          "SCREENOTE_IMAGE=#{ENV.fetch('SCREENOTE_FAKE_IMAGE')}\n" \
            "SCREENOTE_SECRET_KEY_BASE_PATH=#{ENV.fetch('SCREENOTE_FAKE_RESTORED_SECRET_PATH', './secrets/secret_key_base')}\n"
        )
        File.chmod(0600, File.join(operator, ".env"))
        FileUtils.mkdir_p(File.join(operator, "secrets"), mode: 0o700)
        File.binwrite(File.join(operator, "secrets", "secret_key_base"), "restored-#{'s' * 48}")
        File.chmod(0400, File.join(operator, "secrets", "secret_key_base"))
      elsif compose_index && command.include?("script/self_hosted_restore_verify")
        exit 0
      elsif compose_index && command.first == "up"
        File.binwrite(ENV.fetch("SCREENOTE_FAKE_STATE"), "running")
      elsif compose_index && command.include?("script/self_hosted_diagnostics")
        puts '{"status":"ok","checks":{"primary":"ok"}}'
      end
    RUBY
    File.chmod(0o700, path)
  end
end
