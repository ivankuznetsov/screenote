# frozen_string_literal: true

# screenote-edition: self_hosted

require "test_helper"
require "fileutils"
require "json"
require "stringio"
require "tmpdir"

class Screenote::KamalReleaseDeployerTest < ActiveSupport::TestCase
  SOURCE_SHA = ("1" * 40).freeze
  RELEASE_TAG = "v1.0.0"
  MANIFEST_DIGEST = "sha256:#{'c' * 64}"
  TARGET_IMAGE = "localhost:5555/screenote:#{SOURCE_SHA}"

  test "published release commands mirror the exact qualified image before Kamal pulls it" do
    runner = FakeRunner.new
    registry_client = FakeRegistryClient.new([ nil, MANIFEST_DIGEST ])
    stdout = StringIO.new
    stderr = StringIO.new

    status = deployer(runner:, registry_client:, stdout:, stderr:).call

    assert_equal 0, status
    assert_empty stderr.string
    assert_includes stdout.string, "Deploying Screenote v1.0.0 from its qualified image"
    assert_equal [
      [
        :run, RbConfig.ruby, "/fake/kamal", "registry", "setup", "--config-file",
        Rails.root.join("config/deploy.yml").to_s
      ],
      [
        :run, "docker", "buildx", "imagetools", "create", "--tag", TARGET_IMAGE,
        "ghcr.io/ivankuznetsov/screenote@#{MANIFEST_DIGEST}"
      ],
      [
        :run, RbConfig.ruby, "/fake/kamal", "setup", "--config-file",
        Rails.root.join("config/deploy.yml").to_s, "--version", SOURCE_SHA, "--skip-push"
      ]
    ], runner.commands
    assert_equal [ SOURCE_SHA, SOURCE_SHA ], registry_client.tags
  end

  test "an existing exact local mirror is reused without mutation" do
    runner = FakeRunner.new
    registry_client = FakeRegistryClient.new([ MANIFEST_DIGEST, MANIFEST_DIGEST ])

    assert_equal 0, deployer(runner:, registry_client:).call
    assert_not runner.commands.any? { |kind, *command| kind == :run && command.include?("create") }
  end

  test "an existing mismatched local release tag fails before deployment" do
    runner = FakeRunner.new
    registry_client = FakeRegistryClient.new([ "sha256:#{'9' * 64}" ])
    stderr = StringIO.new

    assert_equal 1, deployer(runner:, registry_client:, stderr:).call
    assert_includes stderr.string, "local release tag already points"
    assert_not runner.commands.any? { |kind, *command| kind == :run && command.include?("setup") && command.include?("--skip-push") }
  end

  test "release image controls cannot be overridden" do
    %w[
      --skip-push --skip-hooks -H=true --no-cache --version=untrusted -d=staging
      --skip_push --skip_hooks --no_cache --no_skip_push --no_skip_hooks
      -Hq -qH -dq -qd -dstaging
    ].each do |argument|
      runner = FakeRunner.new
      stderr = StringIO.new

      status = deployer(argv: [ "deploy", argument ], runner:, stderr:).call

      assert_equal 1, status, argument
      assert_includes stderr.string, "release setup manages image version", argument
      assert_equal [], runner.commands, argument
    end
  end

  test "values of supported short options are not mistaken for option clusters" do
    runner = FakeRunner.new
    registry_client = FakeRegistryClient.new([ MANIFEST_DIGEST, MANIFEST_DIGEST ])
    arguments = [ "deploy", "-c=config/deploy.yml", "-h=prod", "-r=backend" ]

    assert_equal 0, deployer(argv: arguments, runner:, registry_client:).call
    final_command = runner.commands.last
    assert_includes final_command, "-h=prod"
    assert_includes final_command, "-r=backend"
    assert_not_includes final_command, "-c=config/deploy.yml"
  end

  test "a checkout with no reachable release tag remains an explicit development preview" do
    runner = FakeRunner.new
    resolver = Struct.new(:release) { def resolve = release }.new(nil)
    stderr = StringIO.new

    status = deployer(runner:, release_resolver: resolver, stderr:).call

    assert_equal 0, status
    assert_includes stderr.string, "development preview"
    assert_equal [ [ :run, RbConfig.ruby, "/fake/kamal", "setup" ] ], runner.commands
  end

  test "Kamal release command abbreviations cannot bypass exact image handling" do
    {
      "set" => "setup",
      "dep" => "deploy",
      "red" => "redeploy"
    }.each do |abbreviation, command|
      runner = FakeRunner.new
      registry_client = FakeRegistryClient.new([ MANIFEST_DIGEST, MANIFEST_DIGEST ])

      assert_equal 0, deployer(argv: [ abbreviation ], runner:, registry_client:).call
      assert_equal command, runner.commands.last.fetch(3), abbreviation
      assert_includes runner.commands.last, "--skip-push", abbreviation
    end
  end

  test "Kamal aliases targeting a release command retain exact image handling" do
    with_starter_config(
      "aliases" => {
        "ship" => "dep -q"
      }
    ) do |root|
      runner = FakeRunner.new
      registry_client = FakeRegistryClient.new([ MANIFEST_DIGEST, MANIFEST_DIGEST ])

      assert_equal 0, deployer(root:, argv: [ "ship" ], runner:, registry_client:).call
      final_command = runner.commands.last
      assert_equal "deploy", final_command.fetch(3)
      assert_includes final_command, "-q"
      assert_includes final_command, "--skip-push"
    end
  end

  test "ambiguous chained or ERB-driven Kamal aliases fail closed" do
    [
      { "ship" => "release-now", "release-now" => "deploy" },
      { "ship" => '<%= ENV.fetch("SHIP_COMMAND", "deploy") %>' },
      { '<%= ENV.fetch("SHIP_ALIAS", "ship") %>' => "deploy" },
      '<%= ENV.fetch("KAMAL_ALIASES", "{ship: deploy}") %>'
    ].each do |aliases|
      with_starter_config("aliases" => aliases) do |root|
        runner = FakeRunner.new
        stderr = StringIO.new

        assert_equal 1, deployer(root:, argv: [ "ship" ], runner:, stderr:).call
        assert_match(/alias|ERB/, stderr.string)
        assert_empty runner.commands
      end
    end
  end

  test "release overrides embedded in a Kamal alias are rejected" do
    with_starter_config("aliases" => { "ship" => "deploy -Hq" }) do |root|
      runner = FakeRunner.new
      stderr = StringIO.new

      assert_equal 1, deployer(root:, argv: [ "ship" ], runner:, stderr:).call
      assert_includes stderr.string, "release setup manages image version"
      assert_empty runner.commands
    end
  end

  test "SaaS and non deployment Kamal commands bypass release handling" do
    [
      [ "logs" ],
      [ "deploy", "--config-file", Rails.root.join("config/deploy.saas.yml").to_s ]
    ].each do |arguments|
      runner = FakeRunner.new

      assert_equal 0, deployer(argv: arguments, runner:).call
      assert_equal [ [ :run, RbConfig.ruby, "/fake/kamal", *arguments ] ], runner.commands
    end
  end

  test "the last repeated config selector controls release handling and all selectors are normalized" do
    runner = FakeRunner.new
    registry_client = FakeRegistryClient.new([ MANIFEST_DIGEST, MANIFEST_DIGEST ])
    arguments = [
      "deploy",
      "-c", Rails.root.join("config/deploy.saas.yml").to_s,
      "--config-file=config/deploy.yml"
    ]

    assert_equal 0, deployer(argv: arguments, runner:, registry_client:).call
    final_command = runner.commands.last
    assert_equal 1, final_command.count("--config-file")
    assert_not final_command.any? { |argument| argument.start_with?("--config-file=") || argument == "-c" }
    assert_includes final_command, Rails.root.join("config/deploy.yml").to_s

    runner = FakeRunner.new
    reversed = [ "deploy", "-c", "config/deploy.yml", "-c=config/deploy.saas.yml" ]
    assert_equal 0, deployer(argv: reversed, runner:).call
    assert_equal [ [ :run, RbConfig.ruby, "/fake/kamal", *reversed ] ], runner.commands

    runner = FakeRunner.new
    underscored = [
      "deploy",
      "--config-file", Rails.root.join("config/deploy.saas.yml").to_s,
      "--config_file=config/deploy.yml"
    ]
    registry_client = FakeRegistryClient.new([ MANIFEST_DIGEST, MANIFEST_DIGEST ])
    assert_equal 0, deployer(argv: underscored, runner:, registry_client:).call
    final_command = runner.commands.last
    assert_equal 1, final_command.count("--config-file")
    assert_not final_command.any? { |argument| argument.start_with?("--config_file") }
  end

  test "relative config selectors follow Kamal's current working directory" do
    Dir.mktmpdir("screenote-kamal-cwd") do |directory|
      arguments = [ "deploy", "--config-file", "config/deploy.yml" ]
      runner = FakeRunner.new

      Dir.chdir(directory) do
        assert_equal 0, deployer(argv: arguments, runner:).call
      end
      assert_equal [ [ :run, RbConfig.ruby, "/fake/kamal", *arguments ] ], runner.commands
    end
  end

  test "a symlink spelling of the starter config cannot bypass release handling" do
    Dir.mktmpdir("screenote-kamal-config-link") do |directory|
      linked_config = Pathname(directory).join("deploy.yml")
      File.symlink(Rails.root.join("config/deploy.yml"), linked_config)
      runner = FakeRunner.new
      registry_client = FakeRegistryClient.new([ MANIFEST_DIGEST, MANIFEST_DIGEST ])

      assert_equal 0, deployer(
        argv: [ "deploy", "--config-file", linked_config.to_s ],
        runner:,
        registry_client:
      ).call
      assert_includes runner.commands.last, "--skip-push"
    end
  end

  test "ERB anywhere in the starter config fails closed before Kamal can change its meaning" do
    with_starter_config({}) do |root|
      File.open(root.join("config/deploy.yml"), "a") do |file|
        file.puts '# <%= "\\naliases:\\n  ship: deploy" %>'
      end
      runner = FakeRunner.new
      stderr = StringIO.new

      assert_equal 1, deployer(root:, argv: [ "ship" ], runner:, stderr:).call
      assert_includes stderr.string, "cannot use ERB"
      assert_empty runner.commands
    end
  end

  test "release evidence must bind identity labels qualification and publication state" do
    mutations = {
      "fixture" => ->(document) { document["fixture"] = true },
      "repository" => ->(document) { document["repository"] = "other/screenote" },
      "source" => ->(document) { document["source_sha"] = "2" * 40 },
      "manifest" => ->(document) { document.dig("artifacts")["manifest_digest"] = "sha256:#{'3' * 64}" },
      "label" => ->(document) { document.dig("artifacts", "oci_labels")["version"] = "v9.9.9" },
      "qualification" => ->(document) { document.dig("qualification")["status"] = "failed" },
      "qualification check" => ->(document) { document.dig("qualification", "checks").pop },
      "publication" => ->(document) { document.dig("public_artifacts")["status"] = "failed" }
    }

    mutations.each do |label, mutation|
      document = evidence_document
      mutation.call(document)

      assert_raises(Screenote::KamalReleaseDeployer::Error, label) do
        Screenote::KamalReleaseDeployer::Evidence.new(
          JSON.generate(document),
          release: release
        ).validate!
      end
    end
  end

  test "release resolver permits only deployment configuration after an exact tag" do
    Dir.mktmpdir("screenote-kamal-release") do |directory|
      run_git(directory, "init", "--quiet")
      run_git(directory, "config", "user.email", "test@example.test")
      run_git(directory, "config", "user.name", "Screenote Test")
      FileUtils.mkdir_p(File.join(directory, "config"))
      File.write(File.join(directory, "config/deploy.yml"), "service: screenote\n")
      File.write(File.join(directory, "application.rb"), "release\n")
      run_git(directory, "add", ".")
      run_git(directory, "commit", "--quiet", "-m", "release")
      run_git(directory, "tag", RELEASE_TAG)
      tagged_sha = capture_git(directory, "rev-parse", "HEAD").strip
      File.write(File.join(directory, "config/deploy.yml"), "service: screenote\nhost: team.example\n")

      resolver = Screenote::KamalReleaseDeployer::ReleaseResolver.new(
        root: Pathname(directory),
        runner: Screenote::KamalReleaseDeployer::CommandRunner.new
      )
      resolved = resolver.resolve

      assert_equal RELEASE_TAG, resolved.tag
      assert_equal tagged_sha, resolved.source_sha

      File.write(File.join(directory, "application.rb"), "customized\n")
      error = assert_raises(Screenote::KamalReleaseDeployer::Error) { resolver.resolve }
      assert_includes error.message, "may change only config/deploy.yml"
    end
  end

  test "release resolver distinguishes no reachable tag from Git inspection failure" do
    Dir.mktmpdir("screenote-kamal-no-release") do |directory|
      run_git(directory, "init", "--quiet")
      run_git(directory, "config", "user.email", "test@example.test")
      run_git(directory, "config", "user.name", "Screenote Test")
      File.write(File.join(directory, "application.rb"), "preview\n")
      run_git(directory, "add", ".")
      run_git(directory, "commit", "--quiet", "-m", "preview")

      resolver = Screenote::KamalReleaseDeployer::ReleaseResolver.new(
        root: Pathname(directory),
        runner: Screenote::KamalReleaseDeployer::CommandRunner.new
      )
      assert_nil resolver.resolve
    end

    runner = CaptureRunner.new([
      [ SOURCE_SHA, "", 0 ],
      [ "", "fatal: corrupt ref", 128 ]
    ])
    resolver = Screenote::KamalReleaseDeployer::ReleaseResolver.new(root: Rails.root, runner:)

    error = assert_raises(Screenote::KamalReleaseDeployer::Error) { resolver.resolve }
    assert_includes error.message, "reachable release tags cannot be inspected"
  end

  private

  def deployer(
    root: Rails.root,
    argv: [ "setup" ],
    runner:,
    stdout: StringIO.new,
    stderr: StringIO.new,
    release_resolver: Struct.new(:release) { def resolve = release }.new(release),
    registry_client: FakeRegistryClient.new([ nil, MANIFEST_DIGEST ])
  )
    Screenote::KamalReleaseDeployer.new(
      root:,
      argv:,
      kamal_bin: "/fake/kamal",
      ruby_bin: RbConfig.ruby,
      env: {},
      stdout:,
      stderr:,
      runner:,
      release_resolver:,
      evidence_fetcher: Struct.new(:contents) { def fetch(_tag) = contents }.new(JSON.generate(evidence_document)),
      registry_client:
    )
  end


  def with_starter_config(overrides)
    Dir.mktmpdir("screenote-kamal-config") do |directory|
      root = Pathname(directory)
      FileUtils.mkdir_p(root.join("config"))
      config = YAML.safe_load(Rails.root.join("config/deploy.yml").read, aliases: true)
      File.write(root.join("config/deploy.yml"), YAML.dump(config.merge(overrides)))
      yield root
    end
  end

  def release
    Screenote::KamalReleaseDeployer::Release.new(tag: RELEASE_TAG, source_sha: SOURCE_SHA)
  end

  def evidence_document
    JSON.parse(Rails.root.join("test/fixtures/releases/valid-redacted-evidence.json").read).tap do |document|
      document["fixture"] = false
    end
  end

  def run_git(directory, *arguments)
    system("git", "-C", directory, *arguments, out: File::NULL, err: File::NULL) ||
      raise("git command failed: #{arguments.join(' ')}")
  end

  def capture_git(directory, *arguments)
    output, error, status = Open3.capture3("git", "-C", directory, *arguments)
    raise error unless status.success?
    output
  end

  class FakeRunner
    attr_reader :commands

    def initialize(run_statuses: [])
      @commands = []
      @run_statuses = run_statuses.dup
    end

    def capture(*command)
      commands << [ :capture, *command ]
      raise "unexpected captured command: #{command.join(' ')}"
    end

    def run(*command)
      commands << [ :run, *command ]
      @run_statuses.shift || 0
    end
  end

  class FakeRegistryClient
    attr_reader :tags

    def initialize(digests)
      @digests = digests.dup
      @tags = []
    end

    def manifest_digest(tag)
      tags << tag
      @digests.shift
    end
  end


  class CaptureRunner
    def initialize(responses)
      @responses = responses.dup
    end

    def capture(*)
      @responses.shift || raise("unexpected captured command")
    end
  end
end
