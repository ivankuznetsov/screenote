# frozen_string_literal: true

require "fileutils"
require "json"
require "net/http"
require "open3"
require "pathname"
require "shellwords"
require "tempfile"
require "uri"
require "yaml"

module Screenote
  class KamalReleaseDeployer
    class Error < StandardError; end

    Release = Data.define(:tag, :source_sha)

    CANONICAL_IMAGE = "ghcr.io/ivankuznetsov/screenote"
    CANONICAL_REPOSITORY = "ivankuznetsov/screenote"
    RELEASE_COMMANDS = %w[setup deploy redeploy].freeze
    RELEASE_TAG = /\Av(?:0|[1-9][0-9]*)\.(?:0|[1-9][0-9]*)\.(?:0|[1-9][0-9]*)\z/
    SHA = /\A[0-9a-f]{40}\z/
    OCI_DIGEST = /\Asha256:[0-9a-f]{64}\z/
    QUALIFICATION_CHECKS = [
      [ "backup-restore", "minimum-host" ],
      [ "public-cli", "http" ],
      [ "public-cli", "https" ],
      [ "saas-boot", "linux-amd64" ],
      [ "saas-boot", "linux-arm64" ],
      [ "self-hosted-boot", "linux-amd64" ],
      [ "self-hosted-boot", "linux-arm64" ],
      [ "sqlite-load", "minimum-host" ]
    ].sort.freeze

    def initialize(
      root:,
      argv:,
      kamal_bin:,
      ruby_bin:,
      env: ENV,
      stdout: $stdout,
      stderr: $stderr,
      runner: nil,
      release_resolver: nil,
      evidence_fetcher: nil,
      registry_client: nil
    )
      @root = Pathname(root).expand_path
      @argv = argv.dup
      @kamal_bin = kamal_bin
      @ruby_bin = ruby_bin
      @env = env
      @stdout = stdout
      @stderr = stderr
      @runner = runner || CommandRunner.new
      @release_resolver = release_resolver || ReleaseResolver.new(root: @root, runner: @runner)
      @evidence_fetcher = evidence_fetcher || EvidenceFetcher.new(root: @root)
      @registry_client = registry_client || RegistryClient.new
    end

    def call
      arguments = release_command_arguments
      return run_kamal(argv) unless arguments

      if env["SCREENOTE_KAMAL_SOURCE_BUILD"] == "1"
        stderr.puts "Screenote warning: building an unqualified development image from the working tree."
        return run_kamal(argv)
      end

      release = release_resolver.resolve
      unless release
        stderr.puts "Screenote development preview: no supported release tag found; Kamal will build this working tree."
        return run_kamal(argv)
      end

      reject_release_overrides!(arguments)
      evidence = Evidence.new(evidence_fetcher.fetch(release.tag), release:).validate!
      validate_starter_config!
      setup_registry!
      mirror_release_image!(release:, evidence:)

      stdout.puts "Deploying Screenote #{release.tag} from its qualified image #{CANONICAL_IMAGE}@#{evidence.manifest_digest}."
      run_kamal(managed_arguments(arguments, release))
    rescue Error => error
      stderr.puts "Screenote release deployment stopped: #{error.message}"
      1
    end

    private

    attr_reader :argv, :env, :evidence_fetcher, :kamal_bin, :release_resolver, :root, :ruby_bin,
      :runner, :registry_client, :stderr, :stdout

    def release_command_arguments
      return unless starter_config_selected?(argv)

      arguments = expand_starter_aliases(argv)
      command = canonical_release_command(arguments.first)
      return unless command

      arguments[0] = command
      arguments if starter_config_selected?(arguments)
    end

    def canonical_release_command(command)
      return unless command

      RELEASE_COMMANDS.find do |candidate|
        command.length >= 3 && candidate.start_with?(command)
      end
    end

    def expand_starter_aliases(original_arguments)
      configuration = starter_configuration
      aliases = configuration.is_a?(Hash) ? configuration.fetch("aliases", {}) : {}
      return original_arguments.dup unless aliases.is_a?(Hash)

      arguments = original_arguments.dup
      return arguments if canonical_release_command(arguments.first)

      command = arguments.first
      target = aliases[command]
      return arguments unless target
      raise Error, "Kamal alias #{command.inspect} must be a command string" unless target.is_a?(String)

      target_arguments = Shellwords.split(target)
      raise Error, "Kamal alias #{command.inspect} has no command" if target_arguments.empty?
      if aliases.key?(target_arguments.first)
        raise Error, "Kamal alias #{command.inspect} cannot chain to another alias"
      end

      target_arguments + arguments.drop(1)
    rescue ArgumentError
      raise Error, "Kamal alias #{command.inspect} cannot be parsed"
    end

    def selected_config(arguments)
      values = arguments.each_with_index.filter_map do |argument, index|
        if argument == "--config-file" || argument == "--config_file" || argument == "-c"
          arguments[index + 1]
        elsif argument.start_with?("--config-file=") || argument.start_with?("--config_file=") ||
            argument.start_with?("-c=")
          argument.split("=", 2).last
        end
      end
      return starter_config if values.empty?

      value = values.last
      return Pathname("/__screenote_invalid_config__") if value.to_s.empty?

      Pathname(value).expand_path
    end

    def starter_config_selected?(arguments)
      selected = selected_config(arguments)
      File.identical?(selected, starter_config)
    rescue Errno::EACCES, Errno::ENOENT, Errno::ELOOP, Errno::ENOTDIR
      selected == starter_config
    end

    def starter_config
      root.join("config/deploy.yml")
    end

    def reject_release_overrides!(arguments)
      prohibited = arguments.select do |argument|
        normalized = argument.start_with?("--") ? argument.tr("_", "-") : argument
        prohibited_short_release_option?(argument) ||
          normalized.start_with?("--skip-push") || normalized.start_with?("--no-skip-push") ||
          normalized.start_with?("--skip-hooks") || normalized.start_with?("--no-skip-hooks") ||
          normalized.start_with?("--no-cache") || normalized.start_with?("--version") ||
          normalized.start_with?("--destination")
      end
      return if prohibited.empty?

      raise Error, "release setup manages image version, pull, and hooks; remove #{prohibited.uniq.join(', ')}"
    end

    def prohibited_short_release_option?(argument)
      return false unless argument.start_with?("-") && !argument.start_with?("--")

      body = argument.delete_prefix("-")
      return false if body.match?(/\A[qvp]+\z/)
      return false if body.match?(/\A[chr](?:=.*)?\z/)

      body.match?(/[PHd]/)
    end

    def starter_configuration
      @starter_configuration ||= begin
        contents = starter_config.read
        raise Error, "config/deploy.yml cannot use ERB with the release-aware wrapper" if contents.include?("<%")

        YAML.safe_load(contents, permitted_classes: [], aliases: true)
      end
    rescue Errno::ENOENT, Psych::Exception => error
      raise Error, "config/deploy.yml is unavailable or invalid (#{error.class})"
    end

    def validate_starter_config!
      config = starter_configuration
      valid = config.is_a?(Hash) && config["service"] == "screenote" && config["image"] == "screenote" &&
        config.dig("registry", "server") == "localhost:5555" && config.dig("builder", "arch") == "amd64"
      raise Error, "config/deploy.yml changed the supported service, registry, or AMD64 target" unless valid
    end

    def setup_registry!
      status = runner.run(ruby_bin, kamal_bin, "registry", "setup", "--config-file", starter_config.to_s)
      raise Error, "Kamal could not start its loopback registry" unless status.zero?
    end

    def mirror_release_image!(release:, evidence:)
      target = "localhost:5555/screenote:#{release.source_sha}"
      existing = registry_client.manifest_digest(release.source_sha)
      if existing
        raise Error, "local release tag already points at #{existing}, expected #{evidence.manifest_digest}" unless
          existing == evidence.manifest_digest
      else
        source = "#{CANONICAL_IMAGE}@#{evidence.manifest_digest}"
        status = runner.run("docker", "buildx", "imagetools", "create", "--tag", target, source)
        raise Error, "Docker Buildx could not mirror the qualified release image" unless status.zero?
      end

      mirrored = registry_client.manifest_digest(release.source_sha)
      raise Error, "mirrored release digest does not match #{evidence.manifest_digest}" unless
        mirrored == evidence.manifest_digest
    end

    def managed_arguments(command_arguments, release)
      arguments = command_arguments.dup
      remove_config_option!(arguments)
      arguments.concat([ "--config-file", starter_config.to_s, "--version", release.source_sha, "--skip-push" ])
    end

    def remove_config_option!(arguments)
      filtered = []
      skip_value = false
      arguments.each do |argument|
        if skip_value
          skip_value = false
        elsif argument == "--config-file" || argument == "--config_file" || argument == "-c"
          skip_value = true
        elsif argument.start_with?("--config-file=") || argument.start_with?("--config_file=") ||
            argument.start_with?("-c=")
          next
        else
          filtered << argument
        end
      end
      arguments.replace(filtered)
    end

    def run_kamal(arguments)
      runner.run(ruby_bin, kamal_bin, *arguments)
    end

    class CommandRunner
      def capture(*command)
        output, error, status = Open3.capture3(*command)
        [ output, error, status.exitstatus || 1 ]
      end

      def run(*command)
        system(*command)
        $?.exitstatus || 1
      end
    end

    class ReleaseResolver
      ALLOWED_RELEASE_CHANGES = [ "config/deploy.yml" ].freeze

      def initialize(root:, runner:)
        @root = root
        @runner = runner
      end

      def resolve
        head, error, status = capture_git("rev-parse", "--verify", "HEAD^{commit}")
        unless status.zero? && head.strip.match?(SHA)
          raise Error, "deployment HEAD cannot be resolved: #{error.strip}"
        end

        reachable_tags, error, status = capture_git("tag", "--merged", "HEAD", "--list", "v[0-9]*")
        raise Error, "reachable release tags cannot be inspected: #{error.strip}" unless status.zero?
        return if reachable_tags.lines.map(&:strip).reject(&:empty?).empty?

        tag, _error, status = capture_git("describe", "--tags", "--abbrev=0", "--match", "v[0-9]*")
        raise Error, "nearest release tag cannot be resolved" unless status.zero?

        tag = tag.strip
        raise Error, "nearest release tag is invalid" unless tag.match?(RELEASE_TAG)

        source_sha, _error, status = capture_git("rev-list", "-n", "1", tag)
        raise Error, "release tag cannot be resolved" unless status.zero?
        source_sha = source_sha.strip
        raise Error, "release tag does not resolve to a full commit" unless source_sha.match?(SHA)

        _output, _error, status = capture_git("merge-base", "--is-ancestor", source_sha, "HEAD")
        raise Error, "release tag is not an ancestor of this deployment branch" unless status.zero?

        changes, error, status = capture_git("diff", "--name-only", "-z", source_sha, "--")
        raise Error, "deployment changes cannot be inspected: #{error.strip}" unless status.zero?
        unsupported = changes.split("\0").reject(&:empty?) - ALLOWED_RELEASE_CHANGES
        raise Error, "supported release branches may change only config/deploy.yml; found #{unsupported.sort.join(', ')}" if
          unsupported.any?

        Release.new(tag:, source_sha:)
      end

      private

      attr_reader :root, :runner

      def capture_git(*arguments)
        runner.capture("git", "-C", root.to_s, *arguments)
      end
    end

    class EvidenceFetcher
      MAX_BYTES = 2 * 1024 * 1024
      MAX_REDIRECTS = 5

      def initialize(root:)
        @root = root
      end

      def fetch(tag)
        path = root.join(".kamal/releases", tag, "public-evidence.json")
        if path.exist? || path.symlink?
          raise Error, "release evidence cache must be one regular file" unless path.file? && !path.symlink?
          raise Error, "release evidence is unexpectedly large" if path.size > MAX_BYTES
          return path.binread
        end

        body = download(
          URI("https://github.com/#{CANONICAL_REPOSITORY}/releases/download/#{tag}/public-evidence.json")
        )
        raise Error, "release evidence is unexpectedly large" if body.bytesize > MAX_BYTES

        FileUtils.mkdir_p(path.dirname)
        Tempfile.create([ "public-evidence", ".json" ], path.dirname) do |file|
          file.binmode
          file.write(body)
          file.flush
          file.fsync
          File.chmod(0o644, file.path)
          File.rename(file.path, path)
        end
        path.binread
      rescue Errno::EACCES, Errno::ENOENT, SystemCallError => error
        raise Error, "release evidence cache failed (#{error.class})"
      end

      private

      attr_reader :root

      def download(uri, redirects = 0)
        raise Error, "release evidence redirected too many times" if redirects > MAX_REDIRECTS
        raise Error, "release evidence requires HTTPS" unless uri.is_a?(URI::HTTPS)

        request = Net::HTTP::Get.new(uri)
        request["Accept"] = "application/json"
        request["User-Agent"] = "screenote-kamal-release/1"
        response = Net::HTTP.start(uri.host, uri.port, use_ssl: true, open_timeout: 10, read_timeout: 30) do |http|
          http.request(request)
        end

        case response
        when Net::HTTPSuccess
          response.body
        when Net::HTTPRedirection
          location = response["location"]
          raise Error, "release evidence redirect is missing a location" if location.to_s.empty?
          download(URI.join(uri, location), redirects + 1)
        else
          raise Error, "release evidence download returned HTTP #{response.code}"
        end
      rescue URI::InvalidURIError, IOError, SocketError, SystemCallError, Timeout::Error => error
        raise Error, "release evidence download failed (#{error.class})"
      end
    end

    class RegistryClient
      ACCEPT = [
        "application/vnd.oci.image.index.v1+json",
        "application/vnd.docker.distribution.manifest.list.v2+json",
        "application/vnd.oci.image.manifest.v1+json",
        "application/vnd.docker.distribution.manifest.v2+json"
      ].join(", ").freeze

      def manifest_digest(tag)
        request = Net::HTTP::Head.new("/v2/screenote/manifests/#{tag}")
        request["Accept"] = ACCEPT
        response = Net::HTTP.start("127.0.0.1", 5555, open_timeout: 5, read_timeout: 10) do |http|
          http.request(request)
        end

        case response
        when Net::HTTPSuccess
          digest = response["docker-content-digest"]
          raise Error, "loopback registry returned an invalid manifest identity" unless
            digest.is_a?(String) && digest.match?(OCI_DIGEST)
          digest
        when Net::HTTPNotFound
          nil
        else
          raise Error, "loopback registry returned HTTP #{response.code} while resolving the release tag"
        end
      rescue IOError, SocketError, SystemCallError, Timeout::Error => error
        raise Error, "loopback registry lookup failed (#{error.class})"
      end
    end

    class Evidence
      attr_reader :manifest_digest

      def initialize(contents, release:)
        @document = JSON.parse(contents)
        @release = release
      rescue JSON::ParserError
        raise Error, "release evidence is not valid JSON"
      end

      def validate!
        require_value(document, "schema", "screenote-release-evidence/v2")
        require_value(document, "fixture", false)
        require_value(document, "repository", CANONICAL_REPOSITORY)
        require_value(document, "source_sha", release.source_sha)

        release_record = require_hash(document, "release")
        require_value(release_record, "tag", release.tag)

        artifacts = require_hash(document, "artifacts")
        require_value(artifacts, "source_sha", release.source_sha)
        @manifest_digest = require_digest(artifacts, "manifest_digest")
        amd64_digest = require_digest(artifacts, "amd64_digest")
        arm64_digest = require_digest(artifacts, "arm64_digest")
        raise Error, "release evidence image digests must be distinct" unless
          [ manifest_digest, amd64_digest, arm64_digest ].uniq.length == 3

        labels = require_hash(artifacts, "oci_labels")
        {
          "source" => "https://github.com/#{CANONICAL_REPOSITORY}",
          "revision" => release.source_sha,
          "version" => release.tag,
          "description" => "Screenote visual feedback workspace",
          "licenses" => "LicenseRef-OSaasy"
        }.each { |key, value| require_value(labels, key, value) }

        qualification = require_hash(document, "qualification")
        require_value(qualification, "status", "passed")
        require_value(qualification, "source_sha", release.source_sha)
        require_value(qualification, "release_tag", release.tag)
        require_value(qualification, "manifest_digest", manifest_digest)
        platforms = require_array(qualification, "platforms")
        qualified_platforms = platforms.to_h do |platform|
          raise Error, "release evidence qualification platform is invalid" unless platform.is_a?(Hash)
          [ platform.fetch("architecture"), platform.fetch("digest") ]
        end
        expected_platforms = { "amd64" => amd64_digest, "arm64" => arm64_digest }
        raise Error, "release evidence qualification platform digests do not match" unless
          platforms.length == 2 && qualified_platforms == expected_platforms
        require_value(qualification, "cli_tag", release_record.fetch("cli_tag"))
        checks = require_array(qualification, "checks")
        identities = checks.filter_map do |check|
          [ check["name"], check["target"] ] if check.is_a?(Hash) && check["status"] == "passed"
        end.sort
        raise Error, "release evidence does not contain every passed qualification check" unless
          identities == QUALIFICATION_CHECKS

        public_artifacts = require_hash(document, "public_artifacts")
        require_value(public_artifacts, "status", "passed")
        require_value(public_artifacts, "sentinel_matches", 0)
        self
      rescue KeyError, TypeError
        raise Error, "release evidence has an invalid structure"
      end

      private

      attr_reader :document, :release

      def require_hash(parent, key)
        value = parent.fetch(key)
        raise Error, "release evidence #{key} must be an object" unless value.is_a?(Hash)
        value
      end

      def require_array(parent, key)
        value = parent.fetch(key)
        raise Error, "release evidence #{key} must be an array" unless value.is_a?(Array)
        value
      end

      def require_digest(parent, key)
        value = parent.fetch(key)
        raise Error, "release evidence #{key} is not an OCI digest" unless value.is_a?(String) && value.match?(OCI_DIGEST)
        value
      end

      def require_value(parent, key, expected)
        actual = parent.fetch(key)
        raise Error, "release evidence #{key} does not match the release" unless actual == expected
        actual
      end
    end
  end
end
