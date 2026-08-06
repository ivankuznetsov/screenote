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

  test "runs one locked maintenance migration before booting only the successor" do
    with_command_fixture do |fixture|
      stdout, stderr, status = run_cutover(fixture)

      assert status.success?, stderr
      assert_includes stdout, "SaaS credential cutover completed"
      assert_equal(
        [
          "lock acquire --message Screenote stopped-process credential cutover",
          "app maintenance --message Screenote credential maintenance",
          "app stop",
          "app containers --quiet",
          "backup create",
          "app exec --primary --version #{fixture.fetch(:version)} " \
            "--env SCREENOTE_SAAS_CREDENTIAL_CUTOVER:authorized " \
            "bin/rails runner script/saas_credential_cutover_migrate",
          "app boot --version #{fixture.fetch(:version)}",
          "app live --version #{fixture.fetch(:version)}",
          "lock release"
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
      assert_equal "lock release", commands.last
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
      assert_operator commands.index("app containers --quiet"), :<, commands.index("backup create")
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
        "app exec --primary --version #{fixture.fetch(:version)} " \
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
    pre_deploy = Rails.root.join(".kamal/hooks/pre-deploy").read
    pre_app_boot = Rails.root.join(".kamal/hooks/pre-app-boot").read
    post_deploy = Rails.root.join(".kamal/hooks/post-deploy").read

    assert_includes pre_deploy, "bin/saas-deploy-guard"
    assert_includes pre_deploy, "KAMAL_VERSION"
    assert_includes pre_app_boot, "--version"
    assert_includes pre_app_boot, "bin/rails db:migrate"
    assert_not_includes post_deploy, "db:migrate"
    assert_not_includes post_deploy, "Running database migrations"
  end

  private

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
