# frozen_string_literal: true

require "digest"
require "fileutils"
require "find"
require "json"
require "open3"
require "pathname"
require "securerandom"
require "tempfile"
require "time"
require "tmpdir"
require_relative "backup_set"

module Screenote
  module SelfHosted
    module HostOperations
      SERVICE = "screenote"
      DEFAULT_TIMEOUT = 120
      VOLUME_NAME_PATTERN = /\A[A-Za-z0-9][A-Za-z0-9_.-]{0,127}\z/
      SUPPORTED_UID = 1000
      DOCKER_ENVIRONMENT_KEYS = %w[
        DOCKER_CERT_PATH
        DOCKER_CONFIG
        DOCKER_CONTEXT
        DOCKER_HOST
        DOCKER_TLS_VERIFY
        HOME
        PATH
        XDG_RUNTIME_DIR
      ].freeze

      class Error < StandardError
        attr_reader :exit_code

        def initialize(message, exit_code: 70)
          @exit_code = exit_code
          super(message)
        end
      end

      class Runner
        attr_reader :docker

        def initialize(docker: ENV.fetch("SCREENOTE_DOCKER_BIN", "docker"))
          @docker = docker
        end

        def capture(*arguments, environment: {}, clean_environment: false)
          Open3.capture3(environment, docker, *arguments, unsetenv_others: clean_environment)
        rescue Errno::ENOENT
          raise Error.new("Docker is unavailable", exit_code: 69)
        end

        def capture!(*arguments, environment: {}, clean_environment: false, message: "Docker command failed")
          stdout, _stderr, status = capture(*arguments, environment:, clean_environment:)
          raise Error, message unless status.success?

          stdout
        end

        def run!(*arguments, environment: {}, clean_environment: false, message: "Docker command failed", preserve_exit: false)
          success = system(environment, docker, *arguments, unsetenv_others: clean_environment)
          return if success

          child_status = $?
          code = preserve_exit && child_status&.exitstatus.to_i.between?(64, 78) ? child_status.exitstatus : 70
          raise Error.new(message, exit_code: code)
        rescue Errno::ENOENT
          raise Error.new("Docker is unavailable", exit_code: 69)
        end
      end

      class Compose
        attr_reader :runner, :files, :project_name, :project_directory, :env_file, :environment,
          :clean_environment

        def initialize(runner:, files:, project_name:, project_directory: nil, env_file: nil, environment: {},
          clean_environment: false)
          @runner = runner
          @files = files
          @project_name = project_name
          @project_directory = project_directory
          @env_file = env_file
          @environment = environment
          @clean_environment = clean_environment
        end

        def arguments
          values = [ "compose" ]
          files.each { |file| values.concat([ "--file", file ]) }
          values.concat([ "--project-name", project_name ])
          values.concat([ "--project-directory", project_directory ]) if project_directory
          values.concat([ "--env-file", env_file ]) if env_file
          values
        end

        def capture!(*command, **options)
          runner.capture!(*arguments, *command, environment:, clean_environment:, **options)
        end

        def capture(*command)
          runner.capture(*arguments, *command, environment:, clean_environment:)
        end

        def run!(*command, **options)
          runner.run!(*arguments, *command, environment:, clean_environment:, **options)
        end
      end

      module Validation
        DOCKER_VOLUME_NAME_PATTERN = /\A[A-Za-z0-9][A-Za-z0-9_.-]{0,254}\z/
        PORTABLE_SECRET_PATH = %r{\A\./secrets/(?:[A-Za-z0-9_.-]+/)*[A-Za-z0-9_.-]+\z}
        COMPOSE_SECRET_VARIABLE = /^\s*file:\s*\$\{([A-Z][A-Z0-9_]*):\?[^}\r\n]+\}\s*$/

        module_function

        def absolute_path!(path, name)
          raise Error.new("#{name} must be an explicit absolute path", exit_code: 64) unless path && Pathname.new(path).absolute?

          File.expand_path(path)
        end

        def compose_files!(files)
          raise Error.new("at least one --compose-file is required", exit_code: 64) if files.empty?

          expanded = files.map { |file| absolute_path!(file, "Compose file") }
          expanded.each { |file| BackupSet.validate_regular_file!(file, description: "Compose file") }
          names = expanded.map { |file| File.basename(file) }
          raise Error.new("Compose filenames must be unique", exit_code: 64) unless names.uniq.length == names.length

          expanded
        rescue BackupSet::Error => error
          raise Error.new(error.message, exit_code: error.exit_code)
        end

        def project_name!(name)
          unless name&.match?(VOLUME_NAME_PATTERN)
            raise Error.new("project name is invalid", exit_code: 64)
          end

          name
        end

        def timeout!(value)
          timeout = Integer(value, 10)
          raise ArgumentError unless timeout.between?(30, 600)

          timeout
        rescue ArgumentError, TypeError
          raise Error.new("timeout must be between 30 and 600 seconds", exit_code: 64)
        end

        def build_compose_contract(files, directory)
          path = File.join(directory, "compose-contract.json")
          body = {
            "schema" => BackupSet::COMPOSE_SCHEMA,
            "files" => files.map do |file|
              { "name" => File.basename(file), "sha256" => Digest::SHA256.file(file).hexdigest }
            end
          }
          File.open(path, File::WRONLY | File::CREAT | File::EXCL, 0o600) { |output| output.write(JSON.generate(body)) }
          path
        end

        def effective_secret_contract!(runtime:, configuration:, secret_bundle:, compose_files:)
          configuration_directory = File.realpath(File.dirname(configuration))
          expected_bundle = File.join(configuration_directory, "secrets")
          canonical_bundle = BackupSet.canonical_existing_directory(secret_bundle, description: "secret bundle")
          unless canonical_bundle == expected_bundle
            raise Error.new("secret bundle must be the portable secrets directory beside the configuration", exit_code: 73)
          end

          rendered = runtime.capture!(
            "config", "--format", "json",
            message: "cannot render the effective Compose secret contract"
          )
          compose = JSON.parse(rendered)
          definitions = compose.fetch("secrets")
          consumed = compose.dig("services", SERVICE, "secrets")
          unless definitions.instance_of?(Hash) && definitions.any? && consumed.instance_of?(Array) && consumed.any?
            raise Error.new("effective Compose secret contract is missing", exit_code: 73)
          end

          sources = consumed.map do |entry|
            unless entry.instance_of?(Hash) && (entry.keys - %w[source target uid gid mode]).empty? &&
                entry["source"].is_a?(String) && entry["target"].is_a?(String) &&
                entry["target"].match?(VOLUME_NAME_PATTERN)
              raise Error.new("effective Compose service secret is invalid", exit_code: 73)
            end
            entry.fetch("source")
          end
          targets = consumed.map { |entry| entry.fetch("target") }
          unless sources.uniq.length == sources.length && targets.uniq.length == targets.length &&
              definitions.keys.sort == sources.sort
            raise Error.new("effective Compose secret sources are ambiguous", exit_code: 73)
          end

          effective_files = sources.map do |source|
            definition = definitions.fetch(source)
            unless definition.instance_of?(Hash) && (definition.keys - %w[file name]).empty? &&
                definition["file"].is_a?(String) && Pathname.new(definition.fetch("file")).absolute?
              raise Error.new("effective Compose secrets must be local file-backed inputs", exit_code: 73)
            end
            BackupSet.validate_regular_file!(
              definition.fetch("file"),
              description: "effective Compose secret file",
              restrictive: true
            )
            File.realpath(definition.fetch("file"))
          end
          unless effective_files.uniq.length == effective_files.length &&
              effective_files.all? { |path| BackupSet.same_or_within?(path, canonical_bundle) }
            raise Error.new("effective Compose secrets must be unique files inside the archived bundle", exit_code: 73)
          end

          secret_variables = compose_files.flat_map do |file|
            File.foreach(file).filter_map { |line| line[COMPOSE_SECRET_VARIABLE, 1] }
          end
          configuration_values = parse_configuration(configuration)
          portable_files = secret_variables.map do |name|
            value = configuration_values[name]
            unless value&.match?(PORTABLE_SECRET_PATH) &&
                value.delete_prefix("./").split("/").none? { |part| part == "." || part == ".." }
              raise Error.new("Compose secret paths must be portable ./secrets paths in the configuration", exit_code: 73)
            end
            File.realpath(File.join(configuration_directory, value))
          end
          unless secret_variables.uniq.length == secret_variables.length && portable_files.sort == effective_files.sort
            raise Error.new("configuration secret paths do not match the effective Compose secrets", exit_code: 73)
          end

          archived_files = []
          Find.find(canonical_bundle) { |path| archived_files << File.realpath(path) if File.file?(path) }
          unless archived_files.sort == effective_files.sort
            raise Error.new("archived secret bundle must contain exactly the effective Compose secret files", exit_code: 73)
          end

          files_by_source = sources.zip(effective_files).to_h
          secret_mounts = consumed.to_h do |entry|
            [ "/run/secrets/#{entry.fetch('target')}", files_by_source.fetch(entry.fetch("source")) ]
          end

          volume_definitions = compose.fetch("volumes")
          service_volumes = compose.dig("services", SERVICE, "volumes")
          unless volume_definitions.instance_of?(Hash) && service_volumes.instance_of?(Array)
            raise Error.new("effective Compose storage contract is missing", exit_code: 73)
          end
          storage_mounts = service_volumes.select do |entry|
            entry.instance_of?(Hash) &&
              (entry["target"] == "/rails/storage" || entry["target"]&.start_with?("/rails/storage/"))
          end
          unless storage_mounts.length == 1
            raise Error.new("effective Compose storage mount is ambiguous", exit_code: 73)
          end
          storage_mount = storage_mounts.fetch(0)
          allowed_mount_keys = %w[type source target read_only volume]
          source = storage_mount["source"]
          unless (storage_mount.keys - allowed_mount_keys).empty? && storage_mount["type"] == "volume" &&
              storage_mount["target"] == "/rails/storage" && storage_mount["read_only"] != true &&
              source.is_a?(String) && storage_mount["volume"].instance_of?(Hash) &&
              storage_mount["volume"].empty? && volume_definitions.keys == [ source ]
            raise Error.new("effective Compose storage must be one writable named volume", exit_code: 73)
          end
          volume_definition = volume_definitions.fetch(source)
          unless volume_definition.instance_of?(Hash) &&
              (volume_definition.keys - %w[name external]).empty? &&
              [ nil, true, false ].include?(volume_definition["external"]) &&
              volume_definition["name"].is_a?(String) &&
              volume_definition["name"].match?(DOCKER_VOLUME_NAME_PATTERN)
            raise Error.new("effective Compose storage volume is invalid", exit_code: 73)
          end

          {
            secret_mounts:,
            storage_volume: volume_definition.fetch("name")
          }
        rescue BackupSet::Error => error
          raise Error.new(error.message, exit_code: 73)
        rescue JSON::ParserError, KeyError, TypeError, Errno::ENOENT, Errno::EACCES
          raise Error.new("effective Compose secret contract is invalid", exit_code: 73)
        end

        def parse_configuration(path)
          File.foreach(path).each_with_object({}) do |line, values|
            next if line.match?(/\A\s*(?:#|\z)/)

            match = line.chomp.match(/\A\s*([A-Z][A-Z0-9_]*)\s*=\s*(.*)\z/)
            raise Error.new("configuration contains an invalid assignment", exit_code: 73) unless match
            raise Error.new("configuration contains a duplicate assignment", exit_code: 73) if values.key?(match[1])

            values[match[1]] = match[2]
          end
        end

        def host_directory!(path, description:, restrictive: false, empty: false)
          canonical = BackupSet.canonical_existing_directory(path, description:)
          stat = File.stat(canonical)
          unless stat.uid == SUPPORTED_UID && stat.gid == SUPPORTED_UID
            raise Error.new("#{description} must be owned by uid/gid 1000", exit_code: 78)
          end
          if restrictive && (stat.mode & 0o077) != 0
            raise Error.new("#{description} permissions must exclude group and other access", exit_code: 78)
          end
          if empty && !Dir.empty?(canonical)
            raise Error.new("#{description} must be empty", exit_code: 73)
          end

          canonical
        rescue BackupSet::Error => error
          raise Error.new(error.message, exit_code: error.exit_code)
        end

        def authentication_key!(path, distinct_files:, outside_directories:, distinct_directories: [])
          expanded = absolute_path!(path, "authentication key")
          bytes = BackupSet.read_authentication_key(expanded)
          key_size = bytes.bytesize
          key_digest = Digest::SHA256.hexdigest(bytes)
          canonical = File.realpath(expanded)
          if outside_directories.any? do |directory|
            BackupSet.same_or_within?(canonical, BackupSet.canonical_existing_directory(directory, description: "archived input"))
          end
            raise Error.new("backup authentication key must be outside every archived input", exit_code: 73)
          end

          key_stat = File.stat(canonical)
          if distinct_files.any? do |file|
            stat = File.stat(file)
            stat.dev == key_stat.dev && stat.ino == key_stat.ino
          end
            raise Error.new("backup authentication key must be a dedicated operator file", exit_code: 73)
          end

          content_candidates = distinct_files.dup
          distinct_directories.each do |directory|
            Find.find(directory) { |entry| content_candidates << entry if File.file?(entry) }
          end
          duplicate_content = content_candidates.uniq.any? do |file|
            stat = File.stat(file)
            stat.size == key_size && BackupSet.secure_digest_match?(Digest::SHA256.file(file).hexdigest, key_digest)
          end
          if duplicate_content
            raise Error.new("backup authentication key must not duplicate archived or recovery input", exit_code: 73)
          end
          canonical
        rescue BackupSet::Error => error
          raise Error.new(error.message, exit_code: error.exit_code)
        rescue Errno::ENOENT, Errno::EACCES
          raise Error.new("backup authentication key is unavailable", exit_code: 73)
        ensure
          bytes&.clear
        end
      end

      class BaseCommand
        def initialize(options, environment: ENV, runner: Runner.new, host_uid: Process.uid)
          @options = options
          @environment = environment
          @runner = runner
          @host_uid = host_uid
          @service_stopped = false
        end

        private

        attr_reader :options, :environment, :runner, :host_uid

        def compose(files: options.fetch(:compose_files), project_directory: nil, env_file: nil, environment: {},
          clean_environment: false)
          Compose.new(
            runner:,
            files:,
            project_name: options.fetch(:project_name),
            project_directory:,
            env_file:,
            environment:,
            clean_environment:
          )
        end

        def docker_environment(extra = {})
          keys = DOCKER_ENVIRONMENT_KEYS
          keys += environment.keys.grep(/\ASCREENOTE_FAKE_/) if environment["RAILS_ENV"] == "test"
          keys.filter_map { |name| [ name, environment[name] ] if environment.key?(name) }.to_h.merge(extra)
        end

        def validate_shared!
          unless host_uid == SUPPORTED_UID
            raise Error.new("self-host operations must run as host uid 1000", exit_code: 78)
          end
          options[:compose_files] = Validation.compose_files!(options.fetch(:compose_files, []))
          options[:project_name] = Validation.project_name!(options.fetch(:project_name, "screenote"))
          options[:timeout] = Validation.timeout!(options.fetch(:timeout, DEFAULT_TIMEOUT).to_s)
          compose.capture!("version", message: "Docker Compose is unavailable")
        end

        def running_container_id(runtime_compose = compose)
          runtime_compose.capture!("ps", "--quiet", SERVICE, message: "cannot inspect the Screenote service").strip
        end

        def inspect_image!(container_id, expected)
          actual = runner.capture!(
            "inspect", "--format", "{{.Config.Image}}", container_id,
            message: "cannot inspect the Screenote image"
          ).strip
          raise Error.new("running image does not match --image", exit_code: 73) unless actual == expected
        end

        def inspect_state!(container_id, expected_status:, require_healthy: false, require_clean_exit: false)
          value = runner.capture!(
            "inspect", "--format",
            "{{.State.Status}}|{{if .State.Health}}{{.State.Health.Status}}{{else}}none{{end}}|" \
              "{{.State.ExitCode}}|{{.State.OOMKilled}}|{{.State.Error}}",
            container_id,
            message: "cannot inspect Screenote process state"
          ).strip
          status, health, exit_code, oom_killed, state_error = value.split("|", 5)
          raise Error.new("Screenote process state is unsafe", exit_code: 73) unless status == expected_status
          if require_healthy && health != "healthy"
            raise Error.new("Screenote must be healthy before backup", exit_code: 75)
          end
          if require_clean_exit && (!%w[0 143].include?(exit_code) || oom_killed != "false" || !state_error.to_s.empty?)
            raise Error.new("Screenote did not stop gracefully", exit_code: 75)
          end
        end

        def stop_service!(container_id, runtime_compose = compose)
          runtime_compose.run!(
            "stop", "--timeout", options.fetch(:timeout).to_s, SERVICE,
            message: "Screenote did not stop gracefully"
          )
          @service_stopped = true
          inspect_state!(container_id, expected_status: "exited", require_clean_exit: true)
        end

        def restart_service!(runtime_compose = compose)
          runtime_compose.run!(
            "up", "--detach", "--no-deps", "--wait", "--wait-timeout", options.fetch(:timeout).to_s, SERVICE,
            message: "Screenote did not become ready after the operation"
          )
          @service_stopped = false
        end

        def service_stopped?
          @service_stopped
        end
      end

      class BackupCommand < BaseCommand
        def call
          validate!
          runtime = backup_compose
          expected_runtime = Validation.effective_secret_contract!(
            runtime:,
            configuration: options.fetch(:configuration),
            secret_bundle: options.fetch(:secret_bundle),
            compose_files: options.fetch(:compose_files)
          )
          container_id = running_container_id(runtime)
          raise Error.new("Screenote must be running before backup", exit_code: 73) if container_id.empty?
          inspect_image!(container_id, options.fetch(:image))
          storage_mountpoint = inspect_runtime_mounts!(container_id, expected_runtime)
          if BackupSet.same_or_within?(options.fetch(:authentication_key), storage_mountpoint)
            raise Error.new("backup authentication key must be outside the running storage volume", exit_code: 73)
          end
          inspect_state!(container_id, expected_status: "running", require_healthy: true)
          stop_service!(container_id, runtime)
          run_s3_snapshot_hook! if options[:s3_snapshot_command]

          Dir.mktmpdir("screenote-backup-contract") do |directory|
            File.chmod(0o700, directory)
            contract = Validation.build_compose_contract(options.fetch(:compose_files), directory)
            run_internal_backup!(contract, runtime)
          end
          restart_service!(runtime)
          puts "Backup finalized at #{options.fetch(:destination)} and Screenote restarted."
          0
        rescue Error => error
          warn "self-host backup: #{error.message}"
          warn "Screenote remains stopped; inspect the failure before restarting it." if service_stopped?
          error.exit_code
        end

        private

        def validate!
          validate_shared!
          %i[destination configuration secret_bundle].each do |name|
            options[name] = Validation.absolute_path!(options[name], name.to_s.tr("_", " "))
          end
          BackupSet.validate_image!(options[:image])
          BackupSet.validate_predecessor!(options[:predecessor], options[:image])
          BackupSet.validate_regular_file!(options[:configuration], description: "configuration", restrictive: true)
          BackupSet.validate_safe_tree!(options[:secret_bundle], description: "secret bundle", restrictive: true)
          validate_s3_hook!
          options[:authentication_key] = Validation.authentication_key!(
            options[:authentication_key],
            distinct_files: [
              options.fetch(:configuration),
              *options.fetch(:compose_files),
              options[:s3_snapshot_command]
            ].compact,
            outside_directories: [ options.fetch(:secret_bundle) ],
            distinct_directories: [ options.fetch(:secret_bundle) ]
          )
          destination_parent = File.dirname(options.fetch(:destination))
          raise Error.new("backup destination already exists", exit_code: 73) if File.exist?(options.fetch(:destination))
          canonical_parent = Validation.host_directory!(
            destination_parent,
            description: "backup destination parent",
            restrictive: true
          )
          options[:destination] = File.join(canonical_parent, File.basename(options.fetch(:destination)))
          canonical_secrets = BackupSet.canonical_existing_directory(
            options.fetch(:secret_bundle),
            description: "secret bundle"
          )
          if BackupSet.same_or_within?(options.fetch(:destination), canonical_secrets)
            raise Error.new("backup destination must be outside the secret bundle", exit_code: 73)
          end
        rescue BackupSet::Error => error
          raise Error.new(error.message, exit_code: error.exit_code)
        rescue Errno::ENOENT, Errno::EACCES
          raise Error.new("backup path is unavailable", exit_code: 73)
        end

        def validate_s3_hook!
          command = options[:s3_snapshot_command]
          evidence = options[:s3_evidence]
          return unless command || evidence
          unless command && evidence
            raise Error.new("--s3-snapshot-command and --s3-evidence must be supplied together", exit_code: 64)
          end
          options[:s3_snapshot_command] = Validation.absolute_path!(command, "S3 snapshot command")
          options[:s3_evidence] = Validation.absolute_path!(evidence, "S3 evidence")
          stat = BackupSet.validate_regular_file!(
            options[:s3_snapshot_command],
            description: "S3 snapshot command",
            restrictive: true
          )
          raise Error.new("S3 snapshot command must be executable", exit_code: 64) if (stat.mode & 0o111).zero?
          raise Error.new("S3 evidence path already exists", exit_code: 73) if File.exist?(options[:s3_evidence])
          evidence_parent = Validation.host_directory!(
            File.dirname(options.fetch(:s3_evidence)),
            description: "S3 evidence parent",
            restrictive: true
          )
          options[:s3_evidence] = File.join(evidence_parent, File.basename(options.fetch(:s3_evidence)))
        end

        def run_s3_snapshot_hook!
          quiesced_at = Time.now.utc.iso8601
          success = system(
            {
              "SCREENOTE_S3_EVIDENCE_PATH" => options.fetch(:s3_evidence),
              "SCREENOTE_BACKUP_QUIESCED_AT" => quiesced_at,
              "SCREENOTE_BACKUP_RESTORE_IMAGE" => options.fetch(:image),
              "SCREENOTE_BACKUP_PREDECESSOR" => options.fetch(:predecessor),
              "SCREENOTE_BACKUP_AGE_RECIPIENT" => options.fetch(:recipient),
              "SCREENOTE_BACKUP_AGE_RECIPIENT_FINGERPRINT" => BackupSet.recipient_fingerprint(
                options.fetch(:recipient)
              )
            },
            options.fetch(:s3_snapshot_command),
            in: File::NULL,
            out: File::NULL,
            err: File::NULL
          )
          raise Error.new("S3 snapshot command failed", exit_code: 75) unless success
          BackupSet.validate_regular_file!(options.fetch(:s3_evidence), description: "S3 backup evidence", restrictive: true)
        rescue BackupSet::Error => error
          raise Error.new(error.message, exit_code: error.exit_code)
        end

        def backup_compose
          @backup_compose ||= compose(
            project_directory: File.dirname(options.fetch(:configuration)),
            env_file: options.fetch(:configuration),
            environment: docker_environment("SCREENOTE_IMAGE" => options.fetch(:image)),
            clean_environment: true
          )
        end

        def inspect_runtime_mounts!(container_id, expected)
          output = runner.capture!(
            "inspect", "--format", "{{json .Mounts}}", container_id,
            message: "cannot inspect running Screenote secret mounts"
          )
          mounts = JSON.parse(output)
          raise Error.new("running Screenote secret mounts are invalid", exit_code: 73) unless mounts.instance_of?(Array)

          secret_mounts = mounts.select do |mount|
            destination = mount.is_a?(Hash) ? mount["Destination"] : nil
            destination == "/run/secrets" || destination&.start_with?("/run/secrets/")
          end
          actual = secret_mounts.to_h do |mount|
            unless mount["Type"] == "bind" && mount["RW"] == false &&
                mount["Source"].is_a?(String) && mount["Destination"].is_a?(String)
              raise Error.new("running Screenote secrets must be read-only bind mounts", exit_code: 73)
            end
            [ mount.fetch("Destination"), File.realpath(mount.fetch("Source")) ]
          end
          unless actual.length == secret_mounts.length && actual == expected.fetch(:secret_mounts)
            raise Error.new("running Screenote secret mounts do not match the archived Compose contract", exit_code: 73)
          end

          storage_mounts = mounts.select do |mount|
            destination = mount.is_a?(Hash) ? mount["Destination"] : nil
            destination == "/rails/storage" || destination&.start_with?("/rails/storage/")
          end
          unless storage_mounts.length == 1
            raise Error.new("running Screenote storage mount is ambiguous", exit_code: 73)
          end
          storage_mount = storage_mounts.fetch(0)
          expected_name = expected.fetch(:storage_volume)
          unless storage_mount["Type"] == "volume" && storage_mount["RW"] == true &&
              storage_mount["Name"] == expected_name && storage_mount["Source"].is_a?(String) &&
              Pathname.new(storage_mount.fetch("Source")).absolute?
            raise Error.new("running Screenote storage volume does not match the archived Compose contract", exit_code: 73)
          end
          volume = JSON.parse(
            runner.capture!(
              "volume", "inspect", "--format", "{{json .}}", expected_name,
              message: "cannot inspect the Screenote storage volume"
            )
          )
          unless volume.instance_of?(Hash) && volume["Name"] == expected_name && volume["Driver"] == "local" &&
              volume["Mountpoint"] == storage_mount["Source"]
            raise Error.new("running Screenote storage volume source is invalid", exit_code: 73)
          end
          File.expand_path(storage_mount.fetch("Source"))
        rescue JSON::ParserError, Errno::ENOENT, Errno::EACCES
          raise Error.new("running Screenote mounts are invalid", exit_code: 73)
        end

        def run_internal_backup!(contract, runtime)
          destination = options.fetch(:destination)
          arguments = [
            "run", "--rm", "--no-deps",
            "--entrypoint", "/rails/script/self_hosted_backup_internal",
            "--volume", "#{File.dirname(destination)}:/screenote-output",
            "--volume", "#{options.fetch(:configuration)}:/screenote-input/configuration:ro",
            "--volume", "#{options.fetch(:secret_bundle)}:/screenote-input/secrets:ro",
            "--volume", "#{options.fetch(:authentication_key)}:/screenote-input/backup-authentication-key:ro",
            "--volume", "#{contract}:/screenote-input/compose-contract.json:ro"
          ]
          if options[:s3_evidence]
            arguments.concat([ "--volume", "#{options.fetch(:s3_evidence)}:/screenote-input/s3-evidence.json:ro" ])
          end
          arguments.concat([
            SERVICE,
            "--storage-root", "/rails/storage",
            "--destination", "/screenote-output/#{File.basename(destination)}",
            "--recipient", options.fetch(:recipient),
            "--configuration", "/screenote-input/configuration",
            "--secret-bundle", "/screenote-input/secrets",
            "--compose-contract", "/screenote-input/compose-contract.json",
            "--authentication-key", "/screenote-input/backup-authentication-key",
            "--image", options.fetch(:image),
            "--predecessor", options.fetch(:predecessor)
          ])
          arguments.concat([ "--s3-evidence", "/screenote-input/s3-evidence.json" ]) if options[:s3_evidence]
          runtime.run!(
            *arguments,
            message: "backup set creation failed",
            preserve_exit: true
          )
        rescue Error => error
          raise Error.new(error.message, exit_code: error.exit_code == 70 ? 75 : error.exit_code)
        end
      end

      class RestoreCommand < BaseCommand
        STORAGE_MOUNT = "/rails/storage"

        def call
          validate!
          authenticate_source!
          ensure_target_volume!
          stop_current_service!

          Dir.mktmpdir("screenote-restore-contract") do |directory|
            File.chmod(0o700, directory)
            contract = Validation.build_compose_contract(options.fetch(:compose_files), directory)
            restore_overlay = build_restore_overlay(directory)
            run_internal_restore!(contract)
            runtime = restored_compose(restore_overlay)
            Validation.effective_secret_contract!(
              runtime:,
              configuration: File.join(options.fetch(:operator_destination), ".env"),
              secret_bundle: File.join(options.fetch(:operator_destination), "secrets"),
              compose_files: options.fetch(:compose_files)
            )
            verify_restored_state!(runtime)
            restart_service!(runtime)
          end
          puts "Restore verified and started #{options.fetch(:image)} on volume #{options.fetch(:target_volume)}."
          0
        rescue Error => error
          warn "self-host restore: #{error.message}"
          warn "No application was started. Keep the explicit target volume for inspection or choose another empty volume." if service_stopped?
          error.exit_code
        end

        private

        def authenticate_source!
          BackupSet.authenticate_completion!(
            source: options.fetch(:source),
            authentication_key: options.fetch(:authentication_key)
          )
        rescue BackupSet::Error => error
          raise Error.new("backup set authentication failed", exit_code: error.exit_code)
        end

        def validate!
          validate_shared!
          %i[source identity operator_destination].each do |name|
            options[name] = Validation.absolute_path!(options[name], name.to_s.tr("_", " "))
          end
          BackupSet.validate_image!(options[:image])
          BackupSet.validate_predecessor!(options[:predecessor], options[:image])
          BackupSet.validate_safe_tree!(options[:source], description: "backup set", restrictive: true)
          BackupSet.validate_regular_file!(options[:identity], description: "age identity", restrictive: true)
          options[:authentication_key] = Validation.authentication_key!(
            options[:authentication_key],
            distinct_files: [ options.fetch(:identity), *options.fetch(:compose_files) ],
            outside_directories: [ options.fetch(:source) ]
          )
          unless options[:target_volume]&.match?(VOLUME_NAME_PATTERN)
            raise Error.new("target volume name is invalid", exit_code: 64)
          end
          options[:source] = BackupSet.canonical_existing_directory(options.fetch(:source), description: "backup set")
          options[:operator_destination] = Validation.host_directory!(
            options.fetch(:operator_destination),
            description: "operator destination",
            restrictive: true,
            empty: true
          )
        rescue BackupSet::Error => error
          raise Error.new(error.message, exit_code: error.exit_code)
        rescue Errno::ENOENT, Errno::EACCES
          raise Error.new("restore path is unavailable", exit_code: 73)
        end

        def stop_current_service!
          container_id = running_container_id
          if container_id.empty?
            @service_stopped = true
            return
          end
          stop_service!(container_id)
        end

        def ensure_target_volume!
          _stdout, _stderr, status = runner.capture("volume", "inspect", options.fetch(:target_volume))
          unless status.success?
            runner.run!("volume", "create", options.fetch(:target_volume), message: "target volume could not be created")
          end
          output = runner.capture!(
            "run", "--rm", "--pull", "never", "--user", "0:0",
            "--entrypoint", "/usr/bin/find",
            "--mount", target_volume_mount,
            options.fetch(:image),
            STORAGE_MOUNT, "-mindepth", "1", "-maxdepth", "1", "-print", "-quit",
            message: "target volume could not be inspected"
          )
          raise Error.new("target volume must be empty", exit_code: 73) unless output.empty?
          runner.run!(
            "run", "--rm", "--pull", "never", "--user", "0:0",
            "--entrypoint", "/bin/chown",
            "--mount", target_volume_mount,
            options.fetch(:image), "1000:1000", STORAGE_MOUNT,
            message: "target volume ownership could not be initialized"
          )
          runner.run!(
            "run", "--rm", "--pull", "never", "--user", "0:0",
            "--entrypoint", "/bin/chmod",
            "--mount", target_volume_mount,
            options.fetch(:image), "0700", STORAGE_MOUNT,
            message: "target volume permissions could not be initialized"
          )
          ownership = runner.capture!(
            "run", "--rm", "--pull", "never", "--user", "1000:1000",
            "--entrypoint", "/bin/stat",
            "--mount", target_volume_mount,
            options.fetch(:image), "--format", "%u:%g:%a", STORAGE_MOUNT,
            message: "target volume ownership could not be verified"
          ).strip
          raise Error.new("target volume must be owned by uid/gid 1000 with mode 0700", exit_code: 78) unless ownership == "1000:1000:700"
        end

        def run_internal_restore!(contract)
          runner.run!(
            "run", "--rm", "--pull", "never", "--user", "1000:1000",
            "--entrypoint", "/rails/script/self_hosted_restore_internal",
            "--mount", target_volume_mount,
            "--volume", "#{options.fetch(:source)}:/screenote-backup:ro",
            "--volume", "#{options.fetch(:identity)}:/screenote-input/identity:ro",
            "--volume", "#{options.fetch(:authentication_key)}:/screenote-input/backup-authentication-key:ro",
            "--volume", "#{options.fetch(:operator_destination)}:/screenote-operator",
            "--volume", "#{contract}:/screenote-input/compose-contract.json:ro",
            options.fetch(:image),
            "--source", "/screenote-backup",
            "--identity", "/screenote-input/identity",
            "--authentication-key", "/screenote-input/backup-authentication-key",
            "--storage-root", "/rails/storage",
            "--operator-destination", "/screenote-operator",
            "--compose-contract", "/screenote-input/compose-contract.json",
            "--image", options.fetch(:image),
            "--predecessor", options.fetch(:predecessor),
            message: "backup set validation or extraction failed",
            preserve_exit: true
          )
        end

        def target_volume_mount
          "type=volume,src=#{options.fetch(:target_volume)},dst=#{STORAGE_MOUNT},volume-nocopy"
        end

        def build_restore_overlay(directory)
          path = File.join(directory, "restore-volume.compose.json")
          body = {
            "volumes" => {
              "screenote_storage" => {
                "external" => true,
                "name" => options.fetch(:target_volume)
              }
            }
          }
          File.open(path, File::WRONLY | File::CREAT | File::EXCL, 0o600) { |file| file.write(JSON.generate(body)) }
          path
        end

        def restored_compose(overlay)
          config = File.join(options.fetch(:operator_destination), ".env")
          BackupSet.validate_regular_file!(config, description: "restored configuration", restrictive: true)
          compose(
            files: [ *options.fetch(:compose_files), overlay ],
            project_directory: options.fetch(:operator_destination),
            env_file: config,
            environment: docker_environment("SCREENOTE_IMAGE" => options.fetch(:image)),
            clean_environment: true
          )
        rescue BackupSet::Error => error
          raise Error.new(error.message, exit_code: error.exit_code)
        end

        def verify_restored_state!(runtime)
          runtime.run!(
            "run", "--rm", "--no-deps", SERVICE,
            "./bin/rails", "runner", "script/self_hosted_restore_verify",
            message: "restored databases or objects failed verification"
          )
        end
      end

      class DiagnosticsCommand < BaseCommand
        def call
          validate_shared!
          container_id = running_container_id
          raise Error.new("Screenote is not running", exit_code: 73) if container_id.empty?
          inspect_state!(container_id, expected_status: "running")
          output = compose.capture!(
            "exec", "--no-tty", SERVICE,
            "/rails/bin/docker-entrypoint", "./bin/rails", "runner", "script/self_hosted_diagnostics",
            message: "diagnostics failed"
          )
          print output
          0
        rescue Error => error
          warn "self-host diagnostics: #{error.message}"
          error.exit_code
        end
      end
    end
  end
end
