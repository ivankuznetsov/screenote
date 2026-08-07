# frozen_string_literal: true

# screenote-edition: self_hosted

require "test_helper"
require "fileutils"
require "json"
require "open3"
require "rbconfig"
require "tmpdir"

class SelfHostedLoadQualificationTest < ActiveSupport::TestCase
  SOURCE_SHA = "1" * 40
  IMAGE = "ghcr.io/ivankuznetsov/screenote@sha256:#{'2' * 64}"
  PROFILE_PATH = Rails.root.join("config/release/minimum-host-v1.json").freeze
  EXPECTED_PROFILE = {
    "schema" => "screenote-minimum-host-profile/v1",
    "id" => "minimum-host-v1",
    "host" => {
      "operating_system" => "linux",
      "architecture" => "amd64",
      "vcpus" => 2,
      "memory_bytes" => 4 * 1024 * 1024 * 1024,
      "storage" => {
        "bytes" => 40 * 1024 * 1024 * 1024,
        "medium" => "ssd",
        "mode" => "local"
      },
      "uid" => 1_000,
      "gid" => 1_000
    },
    "load" => {
      "sessions" => 25,
      "simultaneous_uploads" => 4,
      "upload_bytes" => 20 * 1024 * 1024,
      "mutation_rate_per_second" => 20,
      "duration_seconds" => 10 * 60
    },
    "limits" => {
      "unhandled_lock_errors_max" => 0,
      "lost_mutations_max" => 0,
      "duplicate_mutations_max" => 0,
      "core_p95_ms_exclusive_max" => 1_000,
      "queue_drain_seconds_max" => 300,
      "queue_depth_after_drain_max" => 0,
      "integrity_errors_max" => 0,
      "request_failures_max" => 0
    }
  }.freeze

  FAKE_DRIVER = <<~'RUBY'
    #!/usr/bin/env ruby
    require "json"

    expected = JSON.parse(ENV.fetch("SCREENOTE_LOAD_EXPECTED_PROFILE"))

    load = expected.fetch("load")
    metrics = {
      "unhandled_lock_errors" => 0,
      "lost_mutations" => 0,
      "duplicate_mutations" => 0,
      "core_p95_ms" => 999,
      "queue_drain_seconds" => 300,
      "queue_depth_after_drain" => 0,
      "integrity_errors" => 0,
      "request_failures" => 0
    }
    case ENV["SCREENOTE_TEST_EVIDENCE"]
    when "load-drift"
      load["duration_seconds"] += 1
    when "extra-metric"
      metrics["unreviewed_metric"] = 0
    when "slow"
      metrics["core_p95_ms"] = 1_000
    when "negative"
      metrics["request_failures"] = -1
    end

    puts JSON.generate({
      "schema" => "screenote-load-smoke/v2",
      "source_sha" => ENV.fetch("SCREENOTE_LOAD_SOURCE_SHA"),
      "image_digest" => ENV.fetch("SCREENOTE_LOAD_IMAGE"),
      "host_profile_id" => expected.fetch("id"),
      "profile" => load,
      "metrics" => metrics
    })
  RUBY

  test "minimum host profile is the exact versioned contract" do
    assert_equal EXPECTED_PROFILE, JSON.parse(PROFILE_PATH.binread)
  end

  test "load evidence uses the incompatible v2 protocol" do
    verifier = Rails.root.join("script/self_hosted_load_smoke").binread
    driver = Rails.root.join("script/self_hosted_load_driver").binread

    assert_includes verifier, 'SCHEMA = "screenote-load-smoke/v2"'
    assert_includes driver, 'EVIDENCE_SCHEMA = "screenote-load-smoke/v2"'
    assert_not_includes verifier, "screenote-load-smoke/v1"
    assert_not_includes driver, "screenote-load-smoke/v1"
  end

  test "verifier terminates the complete driver process group on timeout" do
    verifier = Rails.root.join("script/self_hosted_load_smoke").binread
    driver = Rails.root.join("script/self_hosted_load_driver").binread

    assert_includes verifier, "pgroup: true"
    assert_includes verifier, "threads_finish_before?([ wait_thread, *readers ], deadline)"
    assert_includes verifier, 'signal_process_group("TERM", wait_thread.pid)'
    assert_includes verifier, 'signal_process_group("KILL", wait_thread.pid)'
    assert_includes verifier, 'Signal.trap("TERM") { raise Interrupt }'
    assert_includes verifier, 'fail!("driver was interrupted")'
    assert_not_includes verifier, "Timeout.timeout"

    outer_grace = verifier.match(/DRIVER_TERMINATION_GRACE_SECONDS = (\d+)/).captures.fetch(0).to_i
    cleanup_timeout = driver.match(/CLEANUP_TIMEOUT_SECONDS = (\d+)/).captures.fetch(0).to_i
    command_grace = driver.match(/TERMINATION_GRACE_SECONDS = (\d+)/).captures.fetch(0).to_i
    assert_operator outer_grace, :>=, 2 * (cleanup_timeout + command_grace)
  end

  test "load verifier passes the full tracked profile and accepts exact evidence" do
    in_qualification_repository do |root|
      stdout, stderr, status = run_verifier(root)

      assert status.success?, stderr
      assert_equal EXPECTED_PROFILE.fetch("load"), JSON.parse(stdout).fetch("profile")
      assert_includes stderr, "qualification evidence validated"
    end
  end

  test "load verifier rejects unknown profile keys before invoking the driver" do
    in_qualification_repository do |root|
      path = File.join(root, "config/release/minimum-host-v1.json")
      profile = JSON.parse(File.binread(path))
      profile["unreviewed"] = true
      File.binwrite(path, JSON.pretty_generate(profile) << "\n")

      _stdout, stderr, status = run_verifier(root)

      assert_not status.success?
      assert_includes stderr, "minimum-host profile keys do not match the versioned contract"
    end
  end

  test "load verifier rejects workload drift unknown metrics and breached limits" do
    cases = {
      "load-drift" => "evidence profile.duration_seconds does not match the versioned contract",
      "extra-metric" => "metric keys do not match the contract",
      "slow" => "core p95 exceeded 1000ms",
      "negative" => "metric request_failures must be a non-negative finite number"
    }

    in_qualification_repository do |root|
      cases.each do |mode, expected_error|
        _stdout, stderr, status = run_verifier(root, { "SCREENOTE_TEST_EVIDENCE" => mode })

        assert_not status.success?, mode
        assert_includes stderr, expected_error, mode
      end
    end
  end

  test "load verifier rejects symlinked profile and driver paths" do
    in_qualification_repository do |root|
      driver = File.join(root, "script/fake_load_driver")
      driver_link = File.join(root, "script/load_driver_link")
      File.symlink(driver, driver_link)

      _stdout, stderr, status = run_verifier(root, {}, driver: driver_link)

      assert_not status.success?
      assert_includes stderr, "SCREENOTE_LOAD_DRIVER must not be a symlink"
    end

    in_qualification_repository do |root|
      profile = File.join(root, "config/release/minimum-host-v1.json")
      target = File.join(root, "minimum-host-target.json")
      FileUtils.mv(profile, target)
      File.symlink(target, profile)

      _stdout, stderr, status = run_verifier(root)

      assert_not status.success?
      assert_includes stderr, "minimum-host profile must be a regular non-symlink file"
    end
  end

  private

  def in_qualification_repository
    Dir.mktmpdir("screenote-load-qualification") do |root|
      FileUtils.mkdir_p(File.join(root, "script"))
      FileUtils.mkdir_p(File.join(root, "config/release"))
      FileUtils.cp(Rails.root.join("script/self_hosted_load_smoke"), File.join(root, "script"))
      FileUtils.cp(PROFILE_PATH, File.join(root, "config/release/minimum-host-v1.json"))
      File.binwrite(File.join(root, "script/fake_load_driver"), FAKE_DRIVER)
      FileUtils.chmod(0o755, [
        File.join(root, "script/self_hosted_load_smoke"),
        File.join(root, "script/fake_load_driver")
      ])
      system("git", "init", "--quiet", root, exception: true)
      system("git", "-C", root, "add", "script", "config/release/minimum-host-v1.json", exception: true)
      yield root
    end
  end

  def run_verifier(root, environment = {}, driver: File.join(root, "script/fake_load_driver"))
    Open3.capture3(
      {
        "SCREENOTE_LOAD_DRIVER" => driver,
        "SCREENOTE_RELEASE_IMAGE" => IMAGE,
        "SCREENOTE_SOURCE_SHA" => SOURCE_SHA
      }.merge(environment),
      RbConfig.ruby,
      File.join(root, "script/self_hosted_load_smoke")
    )
  end
end
