# frozen_string_literal: true

require "test_helper"
require "digest"
require "fileutils"
require "json"
require "open3"
require "tmpdir"

class SaasCredentialCutoverCommandTest < ActiveSupport::TestCase
  CUTOVER = Rails.root.join("bin/saas-credential-cutover").to_s.freeze
  DEPLOY_GUARD = Rails.root.join("bin/saas-deploy-guard").to_s.freeze
  GUARD_SCRIPT = Rails.root.join("script/saas_deploy_guard").to_s.freeze

  test "runs one locked maintenance migration before booting only the successor" do
    with_command_fixture do |fixture|
      stdout, stderr, status = run_cutover(fixture)

      assert status.success?, stderr
      assert_includes stdout, "SaaS credential cutover completed"
      assert_equal(
        [
          "lock acquire --message Screenote stopped-process credential cutover --config-file config/deploy.saas.yml",
          "app maintenance --message Screenote credential maintenance --config-file config/deploy.saas.yml",
          "app stop --config-file config/deploy.saas.yml",
          "app containers --quiet --config-file config/deploy.saas.yml",
          "backup create",
          "app exec --primary --version #{fixture.fetch(:version)} " \
            "--env SCREENOTE_SAAS_CREDENTIAL_CUTOVER:authorized " \
            "bin/rails runner script/saas_credential_cutover_migrate --config-file config/deploy.saas.yml",
          "app boot --version #{fixture.fetch(:version)} --config-file config/deploy.saas.yml",
          "app live --version #{fixture.fetch(:version)} --config-file config/deploy.saas.yml",
          "lock release --config-file config/deploy.saas.yml"
        ],
        File.readlines(fixture.fetch(:trace), chomp: true)
      )
    end
  end

  test "leaves maintenance active and never migrates while an app process remains" do
    with_command_fixture do |fixture|
      _stdout, stderr, status = run_cutover(fixture, { "SCREENOTE_FAKE_ACTIVE" => "true" })

      assert_not status.success?
      assert_includes stderr, "an application or worker process is still running"
      assert_includes stderr, "remains in maintenance"
      commands = File.readlines(fixture.fetch(:trace), chomp: true)
      assert_equal "lock release --config-file config/deploy.saas.yml", commands.last
      assert_not commands.any? { |command| command.include?("saas_credential_cutover_migrate") }
      assert_not commands.any? { |command| command.start_with?("app boot") }
      assert_not commands.any? { |command| command.start_with?("app live") }
    end
  end

  test "rejects a changed backup hook before taking a deployment lock" do
    with_command_fixture do |fixture|
      _stdout, stderr, status = run_cutover(
        fixture,
        {},
        hook_digest: "0" * 64
      )

      assert_not status.success?
      assert_includes stderr, "backup hook digest does not match"
      assert_not File.exist?(fixture.fetch(:trace))
    end
  end

  test "rejects backup evidence completed before the stopped process window" do
    with_command_fixture do |fixture|
      _stdout, stderr, status = run_cutover(
        fixture,
        { "SCREENOTE_FAKE_PRE_STOP_BACKUP" => "true" }
      )

      assert_not status.success?
      assert_includes stderr, "backup completed before the application was quiesced"
      commands = File.readlines(fixture.fetch(:trace), chomp: true)
      containers = commands.index { |command| command.start_with?("app containers --quiet") }
      assert_operator containers, :<, commands.index("backup create")
      assert_not commands.any? { |command| command.include?("saas_credential_cutover_migrate") }
      assert_not commands.any? { |command| command.start_with?("app boot") }
    end
  end

  test "deploy guard executes the candidate revision and propagates refusal" do
    with_command_fixture do |fixture|
      stdout, stderr, status = Open3.capture3(
        {
          "SCREENOTE_KAMAL_BIN" => fixture.fetch(:kamal),
          "SCREENOTE_FAKE_TRACE" => fixture.fetch(:trace)
        },
        DEPLOY_GUARD,
        fixture.fetch(:version)
      )

      assert status.success?, stderr
      assert_empty stdout
      assert_equal(
        "app --config-file config/deploy.saas.yml exec --primary --version #{fixture.fetch(:version)} " \
          "bin/rails runner script/saas_deploy_guard",
        File.readlines(fixture.fetch(:trace), chomp: true).last
      )

      _stdout, stderr, status = Open3.capture3(
        {
          "SCREENOTE_KAMAL_BIN" => fixture.fetch(:kamal),
          "SCREENOTE_FAKE_TRACE" => fixture.fetch(:trace),
          "SCREENOTE_FAKE_FAIL_GUARD" => "true"
        },
        DEPLOY_GUARD,
        fixture.fetch(:version)
      )

      assert_not status.success?
      assert_includes stderr, "candidate verification failed"
    end
  end

  test "hooks refuse pending cutover before deploy and never migrate after deploy" do
    pre_deploy = Rails.root.join(".kamal/hooks/saas/pre-deploy").read
    pre_app_boot = Rails.root.join(".kamal/hooks/saas/pre-app-boot").read
    post_deploy = Rails.root.join(".kamal/hooks/saas/post-deploy").read

    assert_includes pre_deploy, "bin/saas-deploy-guard"
    assert_includes pre_deploy, "KAMAL_VERSION"
    assert_includes pre_deploy, "deploy|redeploy"
    assert_includes pre_app_boot, "--version"
    assert_includes pre_app_boot, "bin/kamal-saas"
    assert_includes pre_app_boot, "bin/saas-deploy-guard"
    assert_includes pre_app_boot, "bin/rails db:migrate"
    assert_operator pre_app_boot.index("bin/saas-deploy-guard"), :<, pre_app_boot.index("bin/rails db:migrate")
    assert_not_includes post_deploy, "db:migrate"
    assert_not_includes post_deploy, "Running database migrations"
  end

  test "pre-deploy guards deploy and redeploy but leaves fresh setup to pre-app-boot" do
    Dir.mktmpdir("screenote-saas-pre-deploy") do |directory|
      FileUtils.mkdir_p(File.join(directory, "bin"))
      guard = File.join(directory, "bin/saas-deploy-guard")
      trace = File.join(directory, "guard.trace")
      File.write(guard, "#!/usr/bin/env bash\nprintf '%s\\n' \"$1\" >> \"$SCREENOTE_FAKE_TRACE\"\n")
      File.chmod(0o700, guard)

      %w[deploy redeploy setup].each do |command|
        _stdout, stderr, status = Open3.capture3(
          {
            "KAMAL_COMMAND" => command,
            "KAMAL_VERSION" => "1" * 40,
            "SCREENOTE_FAKE_TRACE" => trace
          },
          Rails.root.join(".kamal/hooks/saas/pre-deploy").to_s,
          chdir: directory
        )
        assert status.success?, stderr
      end

      assert_equal [ "1" * 40, "1" * 40 ], File.readlines(trace, chomp: true)
    end
  end

  test "candidate guard allows only an empty database or an applied credential migration" do
    fresh = GuardConnection.new(data_sources: [], applied: false)
    output, error = capture_io do
      with_guard_connection(fresh) { load GUARD_SCRIPT }
    end
    assert_includes output, "Fresh SaaS database"
    assert_empty error

    applied = GuardConnection.new(data_sources: %w[schema_migrations users], applied: true)
    output, error = capture_io do
      with_guard_connection(applied) { load GUARD_SCRIPT }
    end
    assert_includes output, "Credential cutover prerequisite"
    assert_empty error

    partial = GuardConnection.new(data_sources: %w[schema_migrations], applied: false)
    error = assert_raises(SystemExit) do
      capture_io do
        with_guard_connection(partial) { load GUARD_SCRIPT }
      end
    end
    assert_includes error.message, "Refusing a rolling deploy"
  end

  private

  GuardConnection = Data.define(:data_sources, :applied) do
    def data_source_exists?(name)
      data_sources.include?(name)
    end

    def quote(value)
      "'#{value}'"
    end

    def select_value(*)
      applied ? 1 : nil
    end
  end

  def with_guard_connection(connection)
    singleton = ActiveRecord::Base.singleton_class
    original = ActiveRecord::Base.method(:connection)
    singleton.define_method(:connection) { connection }
    yield
  ensure
    singleton&.define_method(:connection, original) if original
  end

  def with_command_fixture
    Dir.mktmpdir("screenote-saas-cutover") do |directory|
      version = `git rev-parse HEAD`.strip
      predecessor = "1" * 40
      trace = File.join(directory, "kamal.trace")
      kamal = File.join(directory, "kamal")
      hook = File.join(directory, "backup-hook")
      evidence = File.join(directory, "backup-evidence.json")
      File.binwrite(kamal, <<~'BASH')
        #!/usr/bin/env bash
        set -Eeuo pipefail
        printf '%s\n' "$*" >> "$SCREENOTE_FAKE_TRACE"
        if [[ "$*" == *"app containers"* && "${SCREENOTE_FAKE_ACTIVE-}" == "true" ]]; then
          printf 'abc image command 1m Up 1 minute ports screenote-web-old\n'
        fi
        if [[ "$*" == *"script/saas_deploy_guard"* && "${SCREENOTE_FAKE_FAIL_GUARD-}" == "true" ]]; then
          exit 73
        fi
      BASH
      File.chmod(0o700, kamal)
      File.binwrite(hook, <<~'RUBY')
        #!/usr/bin/env ruby
        require "digest"
        require "json"
        require "time"

        quiesced_at = Time.iso8601(ENV.fetch("SCREENOTE_CUTOVER_QUIESCED_AT")).utc
        completed_at = if ENV["SCREENOTE_FAKE_PRE_STOP_BACKUP"] == "true"
          quiesced_at - 1
        else
          Time.now.utc
        end
        evidence = {
          "schema" => "screenote-saas-cutover-backup/v1",
          "status" => "verified",
          "predecessor_version" => ENV.fetch("SCREENOTE_CUTOVER_PREDECESSOR"),
          "successor_version" => ENV.fetch("SCREENOTE_CUTOVER_SUCCESSOR"),
          "quiesced_at" => quiesced_at.iso8601(6),
          "quiescence_challenge" => ENV.fetch("SCREENOTE_CUTOVER_CHALLENGE"),
          "completed_at" => completed_at.iso8601(6),
          "restore_tested_at" => (Time.now.utc - 86_400).iso8601(6),
          "backup_reference_sha256" => Digest::SHA256.hexdigest("restricted-backup-reference"),
          "database_restore_point_sha256" => Digest::SHA256.hexdigest("database-restore-point"),
          "database_roles" => %w[primary cache queue cable]
        }
        File.binwrite(ENV.fetch("SCREENOTE_CUTOVER_EVIDENCE_PATH"), JSON.generate(evidence))
        File.chmod(0o600, ENV.fetch("SCREENOTE_CUTOVER_EVIDENCE_PATH"))
        File.open(ENV.fetch("SCREENOTE_FAKE_TRACE"), "a") { |file| file.puts("backup create") }
      RUBY
      File.chmod(0o700, hook)

      yield(
        version:,
        predecessor:,
        trace:,
        kamal:,
        hook:,
        evidence:,
        hook_digest: Digest::SHA256.file(hook).hexdigest
      )
    end
  end

  def run_cutover(fixture, extra_environment = {}, hook_digest: fixture.fetch(:hook_digest))
    Open3.capture3(
      {
        "SCREENOTE_KAMAL_BIN" => fixture.fetch(:kamal),
        "SCREENOTE_FAKE_TRACE" => fixture.fetch(:trace)
      }.merge(extra_environment),
      CUTOVER,
      "--version", fixture.fetch(:version),
      "--predecessor", fixture.fetch(:predecessor),
      "--backup-evidence", fixture.fetch(:evidence),
      "--backup-hook", fixture.fetch(:hook),
      "--backup-hook-sha256", hook_digest
    )
  end
end
