# frozen_string_literal: true

# screenote-edition: self_hosted

require "test_helper"
require "rbconfig"
load Rails.root.join("script/self_hosted_load_driver")

class SelfHostedLoadDriverTest < ActiveSupport::TestCase
  SOURCE_SHA = "1" * 40
  IMAGE = "ghcr.io/ivankuznetsov/screenote@sha256:#{'2' * 64}"

  class SuccessfulStatus
    def success?
      true
    end
  end

  class LifecycleRunner < ScreenoteLoadDriver::Runner
    attr_reader :commands

    def initialize(
      environment,
      inspect_nano_cpus: 2_000_000_000,
      volume_available_blocks: 41_943_041,
      fail_after: nil
    )
      @commands = []
      @inspect_nano_cpus = inspect_nano_cpus
      @volume_available_blocks = volume_available_blocks
      @fail_after = fail_after
      super(environment)
    end

    private

    def processor_count
      2
    end

    def total_memory_bytes
      4 * 1024 * 1024 * 1024
    end

    def available_port
      34_567
    end

    def wait_for_readiness!
      nil
    end

    def seed_load_data!
      { "uploads" => [] }
    end

    def build_exact_png(path, _target_bytes)
      File.binwrite(path, "png")
      path
    end

    def run_workload!(_seed, _image_path)
      { prefix: "screenote-load-test-", expected_count: 1 }
    end

    def reconcile_mutations(_workload)
      { "lost" => 0, "duplicates" => 0 }
    end

    def upload_processing_failures(_seed)
      0
    end

    def capture_command(*command, **options)
      commands << { argv: command, options: options }
      if failing_command?(command)
        @fail_after = nil
        raise ScreenoteLoadDriver::Error, "simulated uncertain Docker completion"
      end

      [ controlled_stdout(command, options), "", SuccessfulStatus.new ]
    end

    def failing_command?(command)
      case @fail_after
      when :volume_create
        command.first(3) == %w[docker volume create]
      when :container_start
        command.first(3) == %w[docker run --detach]
      else
        false
      end
    end

    def controlled_stdout(command, options)
      if command.first(3) == %w[docker image inspect]
        JSON.generate([
          {
            "RepoDigests" => [ IMAGE ],
            "Config" => { "Labels" => { "org.opencontainers.image.revision" => SOURCE_SHA } },
            "Os" => "linux",
            "Architecture" => "amd64"
          }
        ])
      elsif command.first(2) == %w[docker inspect]
        JSON.generate([
          {
            "HostConfig" => {
              "NanoCpus" => @inspect_nano_cpus,
              "Memory" => 4 * 1024 * 1024 * 1024,
              "MemorySwap" => 4 * 1024 * 1024 * 1024
            },
            "Config" => { "User" => "1000:1000" }
          }
        ])
      elsif command.include?("df")
        <<~DF
          Filesystem 1024-blocks Used Available Capacity Mounted on
          screenote-volume 50000000 1 #{@volume_available_blocks} 1% /rails/storage
        DF
      elsif options.fetch(:stdin_data, "").include?("SolidQueue::Job.where")
        JSON.generate("seconds" => 0.125, "depth" => 0)
      elsif command.first(2) == %w[docker exec]
        "ok\n"
      else
        ""
      end
    end
  end

  test "calculates nearest-rank p95 latency" do
    samples = (1..100).map(&:to_f)

    assert_equal 95.0, ScreenoteLoadDriver::Metrics.percentile(samples, 0.95)
    assert_equal 0.0, ScreenoteLoadDriver::Metrics.percentile([], 0.95)
  end

  test "excludes upload latency from the core response percentile" do
    response = Struct.new(:code, :body).new("200", "{}")
    metrics = ScreenoteLoadDriver::Metrics.new

    metrics.record_http(latency_ms: 900, response: response, expected_status: 200, core: false)
    metrics.record_http(latency_ms: 15, response: response, expected_status: 200)

    assert_equal 15, metrics.core_p95_ms
    assert_equal 0, metrics.request_failures
  end

  test "reconciles lost duplicated and unexpected mutation identities" do
    prefix = "screenote-load-test-"
    body = ->(index) { format("%s%012d", prefix, index) }
    actual = [ body.call(0), body.call(1), body.call(1), "#{prefix}unexpected" ]

    assert_equal({ "lost" => 1, "duplicates" => 2 },
      ScreenoteLoadDriver::Runner.reconcile_mutation_bodies(prefix: prefix, expected_count: 3, actual: actual))
  end

  test "accepts the canonical profile contract passed by the verifier" do
    runner = ScreenoteLoadDriver::Runner.new(driver_environment)

    assert_nothing_raised { runner.send(:validate_inputs!) }
  ensure
    runner&.send(:cleanup!)
  end

  test "runs the candidate lifecycle against the exact volume and minimum-host limits" do
    runner = LifecycleRunner.new(driver_environment)

    stdout, = capture_io { runner.run }

    volume = runner.send(:volume)
    container = runner.send(:container)
    commands = runner.commands.pluck(:argv)
    volume_create = [ "docker", "volume", "create", volume ]
    storage_df = [
      "docker", "run", "--rm", "--user", "0", "--entrypoint", "df",
      "--volume", "#{volume}:/rails/storage", IMAGE, "-Pk", "/rails/storage"
    ]
    start = commands.find { |command| command.first(3) == %w[docker run --detach] }

    assert_includes commands, volume_create
    assert_includes commands, storage_df
    assert_operator commands.index(volume_create), :<, commands.index(storage_df)
    assert_equal "2", option_value(start, "--cpus")
    assert_equal "4294967296", option_value(start, "--memory")
    assert_equal "4294967296", option_value(start, "--memory-swap")
    assert_equal "1000:1000", option_value(start, "--user")
    assert_includes start, "DISABLE_SSL=true"
    assert_includes commands, [ "docker", "rm", "--force", container ]
    assert_includes commands, [ "docker", "volume", "rm", "--force", volume ]
    assert runner.commands.all? { |entry| entry.dig(:options, :timeout_seconds).to_f.positive? }

    queue_runner = runner.commands.find do |entry|
      entry.dig(:options, :stdin_data).to_s.include?("SolidQueue::Job.where")
    end
    assert_includes queue_runner.dig(:options, :stdin_data),
      "SolidQueue::Job.where(finished_at: nil).where(scheduled_at: ..Time.current)"
    assert_not_includes queue_runner.dig(:options, :stdin_data), "class_name"
    assert_operator queue_runner.dig(:options, :timeout_seconds), :>=, 330

    evidence = JSON.parse(stdout)
    assert_equal "screenote-load-smoke/v2", evidence.fetch("schema")
    assert_equal SOURCE_SHA, evidence.fetch("source_sha")
    assert_equal IMAGE, evidence.fetch("image_digest")
    assert_equal "minimum-host-v1", evidence.fetch("host_profile_id")
    assert_equal 0, evidence.dig("metrics", "request_failures")
    assert_equal 0, evidence.dig("metrics", "queue_depth_after_drain")
  end

  test "inspect mismatch fails closed and cleans the container and volume" do
    runner = LifecycleRunner.new(driver_environment, inspect_nano_cpus: 1_000_000_000)

    stdout, = capture_io do
      error = assert_raises(ScreenoteLoadDriver::Error) { runner.run }
      assert_equal "candidate CPU limit does not match the minimum-host profile", error.message
    end

    commands = runner.commands.pluck(:argv)
    assert_empty stdout
    assert_includes commands, [ "docker", "rm", "--force", runner.send(:container) ]
    assert_includes commands, [ "docker", "volume", "rm", "--force", runner.send(:volume) ]
  end

  test "insufficient named-volume storage fails before container start and removes the volume" do
    runner = LifecycleRunner.new(driver_environment, volume_available_blocks: 41_943_039)

    error = assert_raises(ScreenoteLoadDriver::Error) { runner.run }

    commands = runner.commands.pluck(:argv)
    assert_equal "minimum host requires 42949672960 free storage bytes", error.message
    assert_not commands.any? { |command| command.first(3) == %w[docker run --detach] }
    assert_includes commands, [ "docker", "volume", "rm", "--force", runner.send(:volume) ]
  end

  test "uncertain Docker creation still removes the deterministic resource names" do
    cases = {
      volume_create: [ "docker", "volume", "rm", "--force" ],
      container_start: [ "docker", "rm", "--force" ]
    }

    cases.each do |failure, cleanup_prefix|
      runner = LifecycleRunner.new(driver_environment, fail_after: failure)

      assert_raises(ScreenoteLoadDriver::Error) { runner.run }

      commands = runner.commands.pluck(:argv)
      cleanup = commands.find { |command| command.first(cleanup_prefix.length) == cleanup_prefix }
      assert_not_nil cleanup, failure
      expected_name = failure == :volume_create ? runner.send(:volume) : runner.send(:container)
      assert_equal expected_name, cleanup.last, failure
    end
  end

  test "bounded subprocess runner kills and reaps a hanging process" do
    runner = ScreenoteLoadDriver::Runner.allocate
    signal_process_group = ScreenoteLoadDriver::Runner.instance_method(:signal_process_group)
    signaled_pid = nil
    runner.define_singleton_method(:signal_process_group) do |signal, pid|
      signaled_pid ||= pid
      signal_process_group.bind_call(self, signal, pid)
    end

    Dir.mktmpdir("screenote-load-driver-hang") do |directory|
      pid_path = File.join(directory, "pid")
      started_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)

      error = assert_raises(ScreenoteLoadDriver::Error) do
        runner.send(
          :capture_command,
          RbConfig.ruby,
          "-e",
          hanging_process_source,
          pid_path,
          timeout_seconds: 0.5,
          termination_grace_seconds: 0.1
        )
      end
      elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started_at

      assert_equal "command timed out: #{RbConfig.ruby}", error.message
      assert_operator elapsed, :<, 2
      assert_not_nil signaled_pid
      assert_raises(Errno::ECHILD) { Process.waitpid(signaled_pid, Process::WNOHANG) }
    end
  end

  test "bounded subprocess runner terminates and reaps on interrupt" do
    runner = ScreenoteLoadDriver::Runner.allocate

    Dir.mktmpdir("screenote-load-driver-interrupt") do |directory|
      pid_path = File.join(directory, "pid")
      interrupted_thread = Thread.current
      interrupter = Thread.new do
        Thread.pass until File.file?(pid_path)
        interrupted_thread.raise(Interrupt)
      end

      assert_raises(Interrupt) do
        runner.send(
          :capture_command,
          RbConfig.ruby,
          "-e",
          hanging_process_source,
          pid_path,
          timeout_seconds: 10,
          termination_grace_seconds: 0.1
        )
      end
      assert_raises(Errno::ECHILD) { Process.waitpid(Integer(File.binread(pid_path)), Process::WNOHANG) }
    ensure
      interrupter&.kill
      interrupter&.join
    end
  end

  test "module entry translates SIGTERM to Interrupt and restores the handler" do
    previous_handler = proc { }
    trap_calls = []
    trap = lambda do |signal, handler = nil, &block|
      trap_calls << { signal: signal, handler: handler, block: block }
      block ? previous_handler : nil
    end
    cleanup_ran = false
    fake_runner = Object.new
    fake_runner.define_singleton_method(:run) do
      trap_calls.first.fetch(:block).call
    ensure
      cleanup_ran = true
    end
    signal_singleton = Signal.singleton_class
    runner_singleton = ScreenoteLoadDriver::Runner.singleton_class
    original_trap = Signal.method(:trap)
    original_new = ScreenoteLoadDriver::Runner.method(:new)
    signal_singleton.send(:define_method, :trap, trap)
    runner_singleton.send(:define_method, :new) { |_environment| fake_runner }

    _stdout, stderr = capture_io do
      assert_equal 130, ScreenoteLoadDriver.run(driver_environment)
    end

    assert cleanup_ran
    assert_includes stderr, "self-hosted load driver: interrupted"
    assert_equal "TERM", trap_calls.first.fetch(:signal)
    assert_same previous_handler, trap_calls.second.fetch(:handler)
  ensure
    signal_singleton&.send(:define_method, :trap, original_trap) if original_trap
    runner_singleton&.send(:define_method, :new, original_new) if original_new
  end

  test "builds an exact-size structurally valid PNG upload" do
    Dir.mktmpdir("screenote-load-driver-test") do |directory|
      runner = ScreenoteLoadDriver::Runner.allocate
      path = File.join(directory, "upload.png")

      runner.send(:build_exact_png, path, 20.megabytes)

      assert_equal 20.megabytes, File.size(path)
      assert_equal "\x89PNG\r\n\x1a\n".b, File.binread(path, 8, 0)
      assert_equal "IEND", File.binread(path, 4, File.size(path) - 8)
    end
  end

  test "requires every client-side upload interval to overlap" do
    runner = ScreenoteLoadDriver::Runner.allocate

    assert runner.send(:uploads_overlap?, [ [ 1.0, 4.0 ], [ 1.5, 3.0 ], [ 2.0, 5.0 ], [ 2.5, 6.0 ] ])
    assert_not runner.send(:uploads_overlap?, [ [ 1.0, 2.0 ], [ 2.1, 3.0 ], [ 1.5, 4.0 ], [ 1.6, 4.0 ] ])
    assert_not runner.send(:uploads_overlap?, [ [ 1.0, 2.0 ], nil ])
  end

  test "driver path is executable" do
    path = Rails.root.join("script/self_hosted_load_driver")

    assert_predicate path, :executable?
    assert_includes path.binread,
      '"/rails/bin/docker-entrypoint", "./bin/rails", "runner", "-"'
    assert_not_includes path.binread, "bootstrap_token"
  end

  private

  def driver_environment
    profile = JSON.parse(Rails.root.join("config/release/minimum-host-v1.json").binread)
    {
      "SCREENOTE_LOAD_EXPECTED_PROFILE" => JSON.generate(profile),
      "SCREENOTE_LOAD_IMAGE" => IMAGE,
      "SCREENOTE_LOAD_SOURCE_SHA" => SOURCE_SHA
    }
  end

  def option_value(command, option)
    command.fetch(command.index(option) + 1)
  end

  def hanging_process_source
    <<~'RUBY'
      File.binwrite(ARGV.fetch(0), Process.pid.to_s)
      Signal.trap("TERM") {}
      STDOUT.write("o" * 262_144)
      STDERR.write("e" * 262_144)
      reader, _writer = IO.pipe
      reader.read
    RUBY
  end
end
