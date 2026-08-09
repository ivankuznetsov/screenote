# frozen_string_literal: true

# screenote-edition: saas

require "test_helper"
require "fileutils"
require "kamal"
require "kamal/version"
require "open3"
require "tmpdir"
require "yaml"

class KamalDeploymentConfigurationTest < ActiveSupport::TestCase
  SAAS_CONFIG = Rails.root.join("config/deploy.saas.yml").freeze

  test "hosted SaaS config stays isolated from public ONCE deployment" do
    config = yaml(SAAS_CONFIG)

    assert_equal "saas", config.dig("env", "clear", "SCREENOTE_EDITION")
    assert_equal "https://screenote.ai", config.dig("env", "clear", "SCREENOTE_BASE_URL")
    assert_equal true, config.dig("env", "clear", "THRUSTER_FORWARD_HEADERS")
    assert_includes config.dig("env", "clear", "SCREENOTE_TRUSTED_PROXIES"), "127.0.0.1/32"
    assert_includes config.dig("env", "clear", "SCREENOTE_TRUSTED_PROXIES"), "::1/128"
    assert_equal ".kamal/hooks/saas", config.fetch("hooks_path")
    assert_equal 900, config.fetch("deploy_timeout")

    kamal = Kamal::Configuration.create_from(config_file: SAAS_CONFIG)
    assert_equal 900, kamal.deploy_timeout
    assert_equal "900s", kamal.proxy.deploy_options.fetch(:"deploy-timeout")

    assert_equal "postgres:16-alpine", config.dig("accessories", "db", "image")
    assert_nil config["volumes"]
    assert_not_includes config.dig("env", "secret"), "SCREENOTE_BOOTSTRAP_TOKEN"
    assert_not_includes config.dig("env", "secret"), "DATABASE_PASSWORD"
  end

  test "SaaS wrapper selects its absolute config before forwarded arguments" do
    Dir.mktmpdir("screenote-kamal-saas") do |root|
      bin = File.join(root, "bin")
      config = File.join(root, "config")
      trace = File.join(root, "kamal-arguments")
      FileUtils.mkdir_p([ bin, config ])
      FileUtils.cp(Rails.root.join("bin/kamal-saas"), File.join(bin, "kamal-saas"))
      FileUtils.chmod(0o700, File.join(bin, "kamal-saas"))
      File.write(File.join(config, "deploy.saas.yml"), "service: screenote\n")
      File.write(
        File.join(bin, "kamal"),
        <<~'BASH'
          #!/usr/bin/env bash
          set -Eeuo pipefail
          printf '%s\0' "$@" > "$SCREENOTE_TEST_TRACE"
        BASH
      )
      FileUtils.chmod(0o700, File.join(bin, "kamal"))

      stdout, stderr, status = Open3.capture3(
        { "SCREENOTE_TEST_TRACE" => trace },
        File.join(bin, "kamal-saas"),
        "deploy",
        "--skip-hooks"
      )

      assert status.success?, stderr
      assert_empty stdout
      assert_empty stderr
      assert_equal(
        [ "deploy", "--config-file", File.join(root, "config/deploy.saas.yml"), "--skip-hooks" ],
        File.binread(trace).split("\0")
      )

      _stdout, stderr, status = Open3.capture3(
        { "SCREENOTE_TEST_TRACE" => trace },
        File.join(bin, "kamal-saas"),
        "app", "exec", "--", "tool", "--config-file", "/tmp/payload.yml",
        "--config_file=/tmp/payload.yml", "-c=/tmp/payload.yml"
      )
      assert status.success?, stderr
      assert_equal(
        [
          "app", "--config-file", File.join(root, "config/deploy.saas.yml"),
          "exec", "--", "tool", "--config-file", "/tmp/payload.yml",
          "--config_file=/tmp/payload.yml", "-c=/tmp/payload.yml"
        ],
        File.binread(trace).split("\0")
      )

      [
        [ "deploy", "--config-file", "/tmp/other.yml" ],
        [ "deploy", "--config_file", "/tmp/other.yml" ],
        [ "deploy", "-c", "/tmp/other.yml" ],
        [ "deploy", "--config-file=/tmp/other.yml" ],
        [ "deploy", "--config_file=/tmp/other.yml" ],
        [ "deploy", "-c=/tmp/other.yml" ]
      ].each do |arguments|
        FileUtils.rm_f(trace)
        stdout, stderr, status = Open3.capture3(
          { "SCREENOTE_TEST_TRACE" => trace },
          File.join(bin, "kamal-saas"),
          *arguments
        )

        assert_equal 64, status.exitstatus, arguments.inspect
        assert_empty stdout
        assert_includes stderr, "do not pass another config selector"
        assert_not File.exist?(trace), arguments.inspect
      end
    end
  end

  test "real Kamal parser configures SaaS before a variadic delimiter" do
    captured_config = nil
    original_exec = Kamal::Cli::App.instance_method(:exec)
    Kamal::Cli::App.define_method(:exec) do |*|
      captured_config = KAMAL.instance_variable_get(:@config_kwargs).fetch(:config_file)
    end
    KAMAL.reset

    Kamal::Cli::Main.start([
      "app", "--config-file", SAAS_CONFIG.to_s,
      "exec", "--", "tool", "--config-file", "/tmp/payload.yml",
      "--config_file=/tmp/payload.yml", "-c=/tmp/payload.yml"
    ])

    assert_equal SAAS_CONFIG.expand_path, captured_config
  ensure
    Kamal::Cli::App.define_method(:exec, original_exec) if original_exec
    KAMAL.reset
  end

  test "SaaS wrapper reaches the real Kamal command parser" do
    stdout, stderr, status = Open3.capture3(Rails.root.join("bin/kamal-saas").to_s, "version")

    assert status.success?, stderr
    assert_equal "#{Kamal::VERSION}\n", stdout
    assert_empty stderr
  end

  test "SaaS post deploy hook uses the isolated Kamal wrapper" do
    post_deploy = Rails.root.join(".kamal/hooks/saas/post-deploy").read

    assert_includes post_deploy, "bin/kamal-saas app exec"
  end

  private

  def yaml(path)
    YAML.safe_load(path.read, aliases: true)
  end
end
