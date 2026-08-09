# frozen_string_literal: true

# screenote-edition: self_hosted

require "test_helper"
require "fileutils"
require "kamal"
require "kamal/version"
require "open3"
require "tmpdir"
require "yaml"

class KamalDeploymentConfigurationTest < ActiveSupport::TestCase
  SELF_HOSTED_CONFIG = Rails.root.join("config/deploy.yml").freeze
  SAAS_CONFIG = Rails.root.join("config/deploy.saas.yml").freeze
  SECRETS_EXAMPLE = Rails.root.join(".kamal/secrets.example").freeze

  test "default Kamal config is a complete self hosted starter" do
    config = yaml(SELF_HOSTED_CONFIG)
    environment = config.dig("env", "clear")
    source = SELF_HOSTED_CONFIG.read

    assert_equal "screenote", config.fetch("service")
    assert_equal "screenote", config.fetch("image")
    assert_equal [ "screenote.example.com" ], config.dig("servers", "web")
    assert_equal "root", config.dig("ssh", "user")

    assert_equal true, config.dig("proxy", "ssl")
    assert_equal "screenote.example.com", config.dig("proxy", "host")
    assert_equal false, config.dig("proxy", "forward_headers")
    assert_equal "/ready", config.dig("proxy", "healthcheck", "path")
    assert_equal 31_457_280, config.dig("proxy", "buffering", "max_request_body")
    assert_equal "/rails/public/assets", config.fetch("asset_path")

    assert_equal "self_hosted", environment.fetch("SCREENOTE_EDITION")
    assert_equal "https://screenote.example.com", environment.fetch("SCREENOTE_BASE_URL")
    assert_equal true, environment.fetch("THRUSTER_FORWARD_HEADERS")
    assert_equal "127.0.0.1/32,::1/128,172.16.0.0/12", environment.fetch("SCREENOTE_TRUSTED_PROXIES")
    assert_equal "local", environment.fetch("SCREENOTE_STORAGE")
    assert_equal false, environment.fetch("SCREENOTE_SMTP_ENABLED")
    assert_equal [ "SECRET_KEY_BASE", "SCREENOTE_BOOTSTRAP_TOKEN" ], config.dig("env", "secret")
    assert_nil environment["SMTP_USERNAME"]
    assert_match(/^    # - SMTP_USERNAME$/, source)
    assert_match(/^    # - SMTP_PASSWORD$/, source)
    assert_equal [ "screenote_storage:/rails/storage" ], config.fetch("volumes")
    assert_equal "2.10.1", config.fetch("minimum_version")
    assert_equal "amd64", config.dig("builder", "arch")
    assert_nil config["accessories"]
    assert_nil config["hooks_path"]
  end

  test "hosted SaaS config stays isolated from the public starter" do
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

  test "tracked secrets template contains no values and covers first boot" do
    secrets = SECRETS_EXAMPLE.read

    assert_match(/^SECRET_KEY_BASE=$/, secrets)
    assert_match(/^SCREENOTE_BOOTSTRAP_TOKEN=$/, secrets)
    assert_match(/^# SMTP_USERNAME=$/, secrets)
    assert_match(/^# SMTP_PASSWORD=$/, secrets)
    refute_match(/^\s*(?:SECRET_KEY_BASE|SCREENOTE_BOOTSTRAP_TOKEN)=.+$/, secrets)
    assert Rails.root.join("bin/kamal-saas").executable?
  end

  test "public setup pins releases and uses the edition aware self hosted gate" do
    readme = Rails.root.join("README.md").read
    contributing = Rails.root.join("CONTRIBUTING.md").read
    guide = Rails.root.join("docs/kamal-deployment.md").read
    operator_guide = Rails.root.join("docs/self-hosting.md").read

    canonical_clone = "git clone --branch vX.Y.Z https://github.com/ivankuznetsov/screenote.git"
    assert_includes readme, canonical_clone
    assert_includes guide, canonical_clone
    assert_includes readme, "git remote rename origin upstream"
    assert_includes guide, "git remote rename origin upstream"
    assert_includes readme, "git fetch upstream tag vNEXT"
    assert_includes guide, "git fetch upstream tag vNEXT"
    assert_includes operator_guide, "git fetch upstream tag vNEXT"
    assert_not_includes readme, "git clone --branch vX.Y.Z https://github.com/YOUR-TEAM/screenote.git"
    assert_not_includes guide, "git clone --branch vX.Y.Z https://github.com/YOUR-TEAM/screenote.git"
    assert_includes readme, "script/release_test_matrix self-hosted"
    assert_includes contributing, "script/release_test_matrix self-hosted"
    assert_not_includes readme, "SCREENOTE_EDITION=self_hosted PARALLEL_WORKERS=1 bin/rails test"
    assert_not_includes contributing, "SCREENOTE_EDITION=self_hosted PARALLEL_WORKERS=1 bin/rails test"
    assert_not_includes readme, "screenote-cli/blob/main/docs/snapshot-manifest.md"
    assert_includes readme, "Linux AMD64"
    assert_includes guide, "Linux AMD64"
    assert_includes readme, "public-evidence.json"
    assert_includes guide, "public-evidence.json"
    assert_includes readme, "SCREENOTE_KAMAL_SOURCE_BUILD=1"
    assert_includes guide, "SCREENOTE_KAMAL_SOURCE_BUILD=1"
    assert_includes Rails.root.join("bin/kamal").read, "KamalReleaseDeployer"
    assert_includes Rails.root.join(".gitignore").read.lines.map(&:strip), "/.kamal/releases/"
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
