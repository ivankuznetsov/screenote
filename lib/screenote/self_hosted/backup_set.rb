# frozen_string_literal: true

require "base64"
require "digest"
require "fileutils"
require "find"
require "json"
require "open3"
require "openssl"
require "pathname"
require "securerandom"
require "sqlite3"
require "stringio"
require "tempfile"
require "time"

module Screenote
  module SelfHosted
    module BackupSet
      SCHEMA = "screenote-self-hosted-backup/v1"
      COMPLETE_SCHEMA = "screenote-self-hosted-backup-complete/v2"
      COMPLETE_AUTHENTICATION_CONTEXT = "screenote-self-hosted-backup-complete-authentication/v1"
      AUTHENTICATION_KEY_FINGERPRINT_CONTEXT = "screenote-self-hosted-backup-authentication-key-fingerprint/v1"
      COMPOSE_SCHEMA = "screenote-compose-contract/v1"
      S3_EVIDENCE_SCHEMA = "screenote-s3-snapshot-evidence/v1"
      DATABASE_ROLES = %w[primary cache queue cable].freeze
      IMAGE_PATTERN = %r{\A[a-z0-9][a-z0-9._/:+-]*@sha256:[0-9a-f]{64}\z}i
      DIGEST_PATTERN = /\A[0-9a-f]{64}\z/
      SCHEMA_VERSION_PATTERN = /\A\d{1,14}\z/
      MAX_JSON_BYTES = 16 * 1024 * 1024
      MAX_AGE_OVERHEAD = 1024 * 1024
      MAX_S3_SNAPSHOT_AGE = 24 * 60 * 60
      MAX_CLOCK_SKEW = 5 * 60
      MAX_QUIESCE_DELAY = 10 * 60
      MIN_AUTHENTICATION_KEY_BYTES = 32
      MAX_AUTHENTICATION_KEY_BYTES = 4096
      COMPLETE_KEYS = %w[
        schema manifest_sha256 authentication_key_fingerprint authentication_hmac_sha256
      ].freeze
      OUTPUT_FILES = %w[COMPLETE configuration.age manifest.json.age secrets.tar.age volume.tar.age].freeze
      S3_OUTPUT_FILE = "s3-evidence.age"
      ARTIFACT_FILES = {
        "configuration" => "configuration.age",
        "secrets" => "secrets.tar.age",
        "volume" => "volume.tar.age",
        "s3_evidence" => S3_OUTPUT_FILE
      }.freeze
      BLOB_KEYS = %w[service key byte_size checksum version].freeze

      class Error < StandardError
        attr_reader :exit_code

        def initialize(message, exit_code: 65)
          @exit_code = exit_code
          super(message)
        end
      end

      module_function

      def sha256_file(path)
        Digest::SHA256.file(path).hexdigest
      end

      def secure_json(path, maximum: MAX_JSON_BYTES)
        stat = File.lstat(path)
        raise Error, "input must be a regular non-symlink file" unless stat.file? && !stat.symlink?
        raise Error, "input is too large" if stat.size > maximum

        value = JSON.parse(File.binread(path))
        raise Error, "input must contain one JSON object" unless value.instance_of?(Hash)

        value
      rescue Errno::ENOENT, Errno::EACCES, JSON::ParserError
        raise Error, "input is unavailable or invalid"
      end

      def validate_exact_keys!(value, keys, description)
        return if value.keys.sort == keys.sort

        raise Error, "#{description} fields are invalid"
      end

      def canonical_object_inventory(objects)
        objects.sort_by { |object| [ object.fetch("service"), object.fetch("key") ] }.map do |object|
          BLOB_KEYS.to_h { |key| [ key, object.fetch(key) ] }
        end
      end

      def object_set_sha256(objects)
        Digest::SHA256.hexdigest(JSON.generate(canonical_object_inventory(objects)))
      end

      def recipient_fingerprint(recipient)
        Digest::SHA256.hexdigest(recipient)
      end

      def read_authentication_key(path)
        File.open(path, File::RDONLY | File::NOFOLLOW | File::NONBLOCK) do |file|
          file.binmode
          stat = file.stat
          unless stat.file? && stat.nlink == 1 && stat.uid == Process.uid && (stat.mode & 0o077).zero?
            raise Error,
              "backup authentication key must be a single-link restricted regular file owned by uid #{Process.uid}"
          end
          unless stat.size.between?(MIN_AUTHENTICATION_KEY_BYTES, MAX_AUTHENTICATION_KEY_BYTES)
            raise Error,
              "backup authentication key must contain #{MIN_AUTHENTICATION_KEY_BYTES} to #{MAX_AUTHENTICATION_KEY_BYTES} bytes"
          end

          bytes = file.read(MAX_AUTHENTICATION_KEY_BYTES + 1)
          unless bytes.bytesize.between?(MIN_AUTHENTICATION_KEY_BYTES, MAX_AUTHENTICATION_KEY_BYTES)
            raise Error,
              "backup authentication key must contain #{MIN_AUTHENTICATION_KEY_BYTES} to #{MAX_AUTHENTICATION_KEY_BYTES} bytes"
          end

          bytes
        end
      rescue Errno::ELOOP, Errno::ENOENT, Errno::EACCES, Errno::ENXIO
        raise Error, "backup authentication key is unavailable"
      end

      def authentication_key_fingerprint(key)
        Digest::SHA256.hexdigest(AUTHENTICATION_KEY_FINGERPRINT_CONTEXT.b + "\0".b + key)
      end

      def completion_authentication_hmac(key, manifest_sha256, key_fingerprint)
        payload = [ COMPLETE_AUTHENTICATION_CONTEXT, manifest_sha256, key_fingerprint ].join("\0").b
        OpenSSL::HMAC.hexdigest("SHA256", key, payload)
      end

      def secure_digest_match?(left, right)
        return false unless left.is_a?(String) && right.is_a?(String) && left.bytesize == right.bytesize

        OpenSSL.fixed_length_secure_compare(left, right)
      end

      def authenticate_completion!(source:, authentication_key:)
        key = nil
        backup_source = canonical_existing_directory(source, description: "backup set")
        marker_path = File.join(backup_source, "COMPLETE")
        validate_regular_file!(marker_path, description: "completion marker", restrictive: true)
        marker = secure_json(marker_path, maximum: 4096)
        validate_exact_keys!(marker, COMPLETE_KEYS, "completion marker")
        unless marker["schema"] == COMPLETE_SCHEMA &&
            marker["manifest_sha256"]&.match?(DIGEST_PATTERN) &&
            marker["authentication_key_fingerprint"]&.match?(DIGEST_PATTERN) &&
            marker["authentication_hmac_sha256"]&.match?(DIGEST_PATTERN)
          raise Error, "backup set is unfinalized"
        end

        manifest_path = File.join(backup_source, "manifest.json.age")
        manifest_stat = validate_regular_file!(
          manifest_path,
          description: "encrypted backup manifest",
          restrictive: true
        )
        if manifest_stat.size > MAX_JSON_BYTES + MAX_AGE_OVERHEAD
          raise Error, "encrypted backup manifest is too large"
        end
        unless secure_digest_match?(sha256_file(manifest_path), marker.fetch("manifest_sha256"))
          raise Error, "encrypted backup manifest digest does not match"
        end

        key = read_authentication_key(authentication_key)
        expected_fingerprint = authentication_key_fingerprint(key)
        expected_hmac = completion_authentication_hmac(
          key,
          marker.fetch("manifest_sha256"),
          marker.fetch("authentication_key_fingerprint")
        )
        fingerprint_matches = secure_digest_match?(
          marker.fetch("authentication_key_fingerprint"),
          expected_fingerprint
        )
        hmac_matches = secure_digest_match?(
          marker.fetch("authentication_hmac_sha256"),
          expected_hmac
        )
        raise Error, "completion marker authentication failed" unless fingerprint_matches & hmac_matches

        marker
      ensure
        key&.clear
      end

      def validate_blob_fields!(blob, expected_service:)
        validate_exact_keys!(blob, BLOB_KEYS, "blob inventory entry")
        key = blob["key"]
        safe_key = key.instance_of?(String) && key.bytesize.between?(1, 1024) &&
          !key.match?(/[[:cntrl:]]/) && !Pathname.new(key).absolute? &&
          Pathname.new(key).each_filename.none? { |component| component == ".." }
        checksum = blob["checksum"]
        valid_checksum = checksum.is_a?(String) && begin
          Base64.strict_decode64(checksum).bytesize == 16
        rescue ArgumentError
          false
        end
        unless blob["service"] == expected_service && safe_key &&
            blob["byte_size"].is_a?(Integer) && blob["byte_size"] >= 0 && valid_checksum
          raise Error, "blob inventory entry is invalid"
        end
      end

      def validate_compose_contract!(value)
        validate_exact_keys!(value, %w[schema files], "Compose contract")
        raise Error, "Compose contract schema is unsupported" unless value["schema"] == COMPOSE_SCHEMA

        files = value["files"]
        unless files.instance_of?(Array) && files.any? && files.all? { |file|
          file.instance_of?(Hash) && file.keys.sort == %w[name sha256] &&
            file["name"].is_a?(String) && file["name"].match?(/\A[A-Za-z0-9._-]+\z/) &&
            file["sha256"].is_a?(String) && file["sha256"].match?(DIGEST_PATTERN)
        }
          raise Error, "Compose contract files are invalid"
        end
        raise Error, "Compose contract filenames must be unique" unless files.map { |file| file["name"] }.uniq.length == files.length

        value
      end

      def canonical_existing_directory(path, description:)
        stat = File.lstat(path)
        raise Error, "#{description} must be a non-symlink directory" unless stat.directory? && !stat.symlink?

        File.realpath(path)
      rescue Errno::ENOENT, Errno::EACCES
        raise Error, "#{description} is unavailable"
      end

      def same_or_within?(candidate, root)
        candidate == root || candidate.start_with?("#{root}/")
      end

      def validate_backup_path_relationships!(storage_root:, destination:, configuration:, secret_bundle:)
        canonical_storage = canonical_existing_directory(storage_root, description: "storage volume")
        canonical_secrets = canonical_existing_directory(secret_bundle, description: "secret bundle")
        canonical_configuration = File.realpath(configuration)
        canonical_destination_parent = canonical_existing_directory(
          File.dirname(destination),
          description: "backup destination parent"
        )
        canonical_destination = File.join(canonical_destination_parent, File.basename(destination))
        if same_or_within?(canonical_configuration, canonical_storage) ||
            same_or_within?(canonical_secrets, canonical_storage)
          raise Error, "configuration and secrets must be outside the storage volume"
        end
        if same_or_within?(canonical_destination, canonical_storage) ||
            same_or_within?(canonical_destination, canonical_secrets)
          raise Error, "backup destination must be outside storage and secret inputs"
        end

        {
          storage_root: canonical_storage,
          destination: canonical_destination,
          configuration: canonical_configuration,
          secret_bundle: canonical_secrets
        }
      rescue Errno::ENOENT, Errno::EACCES
        raise Error, "backup input path is unavailable"
      end

      def validate_image!(value, name: "image")
        raise Error, "#{name} must be an immutable image reference" unless value&.match?(IMAGE_PATTERN)
      end

      def validate_predecessor!(value, image)
        return if value == "none"

        validate_image!(value, name: "predecessor")
        raise Error, "predecessor must differ from the restore image" if value == image
      end

      def validate_regular_file!(path, description:, restrictive: false)
        stat = File.lstat(path)
        raise Error, "#{description} must be a regular non-symlink file" unless stat.file? && !stat.symlink?
        raise Error, "#{description} must be owned by uid #{Process.uid}" unless stat.uid == Process.uid
        if restrictive && (stat.mode & 0o077) != 0
          raise Error, "#{description} permissions must exclude group and other access"
        end

        stat
      rescue Errno::ENOENT, Errno::EACCES
        raise Error, "#{description} is unavailable"
      end

      def validate_safe_tree!(root, description:, restrictive: false)
        root_stat = File.lstat(root)
        raise Error, "#{description} must be a non-symlink directory" unless root_stat.directory? && !root_stat.symlink?

        Find.find(root) do |path|
          stat = File.lstat(path)
          relative = path.delete_prefix("#{root}/")
          if stat.symlink?
            raise Error, "#{description} must not contain symlinks"
          end
          unless stat.directory? || stat.file?
            raise Error, "#{description} must contain only regular files and directories"
          end
          if relative.match?(/[\u0000-\u001f\u007f]/)
            raise Error, "#{description} contains an unsupported path"
          end
          raise Error, "#{description} must be owned by uid #{Process.uid}" unless stat.uid == Process.uid
          if restrictive && (stat.mode & 0o077) != 0
            raise Error, "#{description} permissions must exclude group and other access"
          end
        end
      rescue Errno::ENOENT, Errno::EACCES
        raise Error, "#{description} is unavailable"
      end

      class DatabaseInspector
        attr_reader :root

        def initialize(root)
          @root = File.expand_path(root)
        end

        def inspect!
          database_manifest = DATABASE_ROLES.to_h do |role|
            path = database_path(role)
            validate_database!(path, role)
            [ role, { "file" => File.basename(path), "schema_version" => schema_version(path) } ]
          end

          installation = installation_identity
          blobs = blob_inventory
          validate_blob_services!(installation.fetch("storage_service"), blobs)
          if installation.fetch("storage_service") == "self_hosted_local"
            blobs.each { |blob| add_local_object_evidence!(blob) }
          end

          {
            "databases" => database_manifest,
            "installation" => installation,
            "blobs" => blobs
          }
        end

        private

        def database_path(role)
          File.join(root, "#{role}.sqlite3")
        end

        def open_database(path)
          SQLite3::Database.new("file:#{path}?mode=ro", uri: true)
        rescue SQLite3::Exception
          raise Error, "#{File.basename(path)} is unavailable or invalid"
        end

        def validate_database!(path, role)
          BackupSet.validate_regular_file!(path, description: "#{role} database")
          database = open_database(path)
          integrity = database.get_first_value("PRAGMA integrity_check")
          raise Error, "#{role} database integrity check failed" unless integrity == "ok"
          raise Error, "#{role} database foreign-key check failed" unless database.execute("PRAGMA foreign_key_check").empty?
        rescue SQLite3::Exception
          raise Error, "#{role} database validation failed"
        ensure
          database&.close
        end

        def schema_version(path)
          database = open_database(path)
          version = database.get_first_value("SELECT MAX(version) FROM schema_migrations").to_s
          raise Error, "#{File.basename(path)} has an invalid schema version" unless version.match?(SCHEMA_VERSION_PATTERN)

          version
        rescue SQLite3::Exception
          raise Error, "#{File.basename(path)} has no readable schema version"
        ensure
          database&.close
        end

        def installation_identity
          database = open_database(database_path("primary"))
          rows = database.execute(<<~SQL)
            SELECT singleton_key, deployment_mode, storage_service, storage_namespace_fingerprint
            FROM installations
          SQL
          unless rows.length == 1 && rows.first[0] == "screenote" && rows.first[1] == "self_hosted"
            raise Error, "primary database does not contain one self-hosted installation"
          end
          service = rows.first[2]
          fingerprint = rows.first[3]
          unless %w[self_hosted_local self_hosted_s3].include?(service) && fingerprint&.match?(DIGEST_PATTERN)
            raise Error, "primary database storage identity is invalid"
          end

          { "storage_service" => service, "storage_namespace_fingerprint" => fingerprint }
        rescue SQLite3::Exception
          raise Error, "primary database installation identity is invalid"
        ensure
          database&.close
        end

        def blob_inventory
          database = open_database(database_path("primary"))
          database.execute(<<~SQL).map do |service, key, byte_size, checksum|
            SELECT service_name, key, byte_size, checksum
            FROM active_storage_blobs
            ORDER BY service_name, key
          SQL
            unless service.instance_of?(String) && key.instance_of?(String) && !key.empty? &&
                byte_size.is_a?(Integer) && byte_size >= 0
              raise Error, "primary database blob inventory is invalid"
            end
            {
              "service" => service,
              "key" => key,
              "byte_size" => byte_size,
              "checksum" => checksum
            }
          end
        rescue SQLite3::Exception
          raise Error, "primary database blob inventory is unavailable"
        ensure
          database&.close
        end

        def validate_blob_services!(service, blobs)
          blobs.each do |blob|
            probe = blob.merge("version" => "pending")
            BackupSet.validate_blob_fields!(probe, expected_service: service)
          end
          return if blobs.map { |blob| blob.fetch("key") }.uniq.length == blobs.length

          raise Error, "database blob inventory contains duplicate keys"
        end

        def add_local_object_evidence!(blob)
          key = blob.fetch("key")
          path = File.join(root, "blobs", key[0, 2], key[2, 2], key)
          stat = BackupSet.validate_regular_file!(path, description: "local blob")
          raise Error, "local blob size does not match the database" unless stat.size == blob.fetch("byte_size")

          digest = Digest::MD5.file(path).digest
          checksum = blob.fetch("checksum")
          if checksum && !secure_equal?(Base64.strict_encode64(digest), checksum)
            raise Error, "local blob checksum does not match the database"
          end
          blob["version"] = BackupSet.sha256_file(path)
        end

        def secure_equal?(left, right)
          return false unless left.bytesize == right.bytesize

          result = 0
          left.bytes.zip(right.bytes) { |first, second| result |= first ^ second }
          result.zero?
        end
      end

      class S3Evidence
        KEYS = %w[
          schema status namespace_fingerprint snapshot_reference snapshot_started_at
          snapshot_completed_at backup_quiesced_at object_set_encryption object_set_sha256 objects
        ].freeze
        ENCRYPTION_KEYS = %w[scheme recipient_fingerprint authenticated].freeze

        def self.load!(path, installation:, blobs:, recipient_fingerprint:, now: Time.now.utc, enforce_freshness: false)
          evidence = BackupSet.secure_json(path)
          BackupSet.validate_exact_keys!(evidence, KEYS, "S3 backup evidence")
          raise Error, "S3 backup evidence schema is unsupported" unless evidence["schema"] == S3_EVIDENCE_SCHEMA
          raise Error, "S3 backup evidence is not finalized" unless evidence["status"] == "finalized"
          unless evidence["namespace_fingerprint"] == installation.fetch("storage_namespace_fingerprint")
            raise Error, "S3 backup evidence namespace does not match"
          end
          unless evidence["snapshot_reference"].instance_of?(String) && evidence["snapshot_reference"].match?(/\A[A-Za-z0-9._:+\/-]{1,512}\z/)
            raise Error, "S3 backup evidence snapshot reference is invalid"
          end
          encryption = evidence["object_set_encryption"]
          raise Error, "S3 backup object set encryption is invalid" unless encryption.instance_of?(Hash)
          BackupSet.validate_exact_keys!(encryption, ENCRYPTION_KEYS, "S3 object-set encryption")
          unless encryption == {
            "scheme" => "age",
            "recipient_fingerprint" => recipient_fingerprint,
            "authenticated" => true
          }
            raise Error, "S3 backup object set must be authenticated age ciphertext for the backup recipient"
          end
          started = parse_time(evidence["snapshot_started_at"], "snapshot_started_at")
          completed = parse_time(evidence["snapshot_completed_at"], "snapshot_completed_at")
          quiesced = parse_time(evidence["backup_quiesced_at"], "backup_quiesced_at")
          raise Error, "S3 backup evidence completion precedes its start" if completed < started
          raise Error, "S3 backup started before the application quiesced" if started < quiesced
          raise Error, "S3 backup evidence is outside the quiesced boundary" if started - quiesced > MAX_QUIESCE_DELAY
          if enforce_freshness
            raise Error, "S3 backup evidence is stale" if now - completed > MAX_S3_SNAPSHOT_AGE
            raise Error, "S3 backup evidence is from the future" if completed - now > MAX_CLOCK_SKEW
          end
          raise Error, "S3 backup took too long" if completed - started > MAX_S3_SNAPSHOT_AGE

          objects = evidence["objects"]
          raise Error, "S3 backup evidence object inventory is invalid" unless objects.instance_of?(Array)
          normalized = objects.map do |object|
            raise Error, "S3 backup evidence object is invalid" unless object.instance_of?(Hash)
            BackupSet.validate_exact_keys!(object, BLOB_KEYS, "S3 backup object")
            unless object["service"] == "self_hosted_s3" && object["key"].is_a?(String) && !object["key"].empty? &&
                object["key"].bytesize <= 1024 && !object["key"].match?(/[[:cntrl:]]/) &&
                object["byte_size"].is_a?(Integer) && object["byte_size"] >= 0 &&
                object["checksum"].is_a?(String)
              raise Error, "S3 backup object is invalid"
            end
            unless object["version"].is_a?(String) && object["version"].match?(/\A[A-Za-z0-9._:+\/-]{1,512}\z/)
              raise Error, "S3 backup object version is invalid"
            end
            object
          end.sort_by { |object| [ object["service"].to_s, object["key"].to_s ] }
          raise Error, "S3 backup evidence contains duplicate objects" unless normalized.map { |object| [ object["service"], object["key"] ] }.uniq.length == normalized.length

          expected = blobs.map { |blob| blob.merge("version" => normalized.find {
            |object| object["service"] == blob["service"] && object["key"] == blob["key"]
          }&.fetch("version", nil)) }.sort_by { |blob| [ blob["service"], blob["key"] ] }
          raise Error, "S3 backup evidence does not match every database blob" unless normalized == expected
          unless evidence["object_set_sha256"].is_a?(String) &&
              evidence["object_set_sha256"].match?(DIGEST_PATTERN) &&
              evidence["object_set_sha256"] == BackupSet.object_set_sha256(normalized)
            raise Error, "S3 backup evidence object-set digest is invalid"
          end

          evidence
        end

        def self.parse_time(value, field)
          raise Error, "S3 backup evidence #{field} is invalid" unless value.instance_of?(String)

          Time.iso8601(value).utc
        rescue ArgumentError
          raise Error, "S3 backup evidence #{field} is invalid"
        end
      end

      class Creator
        MANIFEST_KEYS = %w[
          schema finalized created_at restore_image predecessor age_recipient_fingerprint configuration_fingerprint
          storage_service storage_namespace_fingerprint database_roles blobs artifacts compose_contract
        ].freeze

        def initialize(storage_root:, destination:, recipient:, configuration:, secret_bundle:,
          compose_contract:, authentication_key:, image:, predecessor:, s3_evidence: nil,
          age: ENV.fetch("SCREENOTE_AGE_BIN", "age"),
          tar: ENV.fetch("SCREENOTE_TAR_BIN", "tar"), now: Time.now.utc)
          @storage_root = File.expand_path(storage_root)
          @destination = File.expand_path(destination)
          @recipient = recipient
          @configuration = File.expand_path(configuration)
          @secret_bundle = File.expand_path(secret_bundle)
          @compose_contract_path = File.expand_path(compose_contract)
          @authentication_key_path = File.expand_path(authentication_key)
          @image = image
          @predecessor = predecessor
          @s3_evidence_path = s3_evidence && File.expand_path(s3_evidence)
          @age = age
          @tar = tar
          @now = now
          @partial = nil
          @authentication_key_bytes = nil
        end

        def call
          inspection = validate!
          create_partial!
          artifacts = {}
          artifacts["volume"] = encrypt_tar(storage_root, "volume.tar.age")
          artifacts["configuration"] = encrypt_file(configuration, "configuration.age")
          artifacts["secrets"] = encrypt_tar(secret_bundle, "secrets.tar.age")
          if s3_evidence_path
            artifacts["s3_evidence"] = encrypt_file(s3_evidence_path, S3_OUTPUT_FILE)
          end

          manifest = build_manifest(inspection, artifacts)
          manifest_path = File.join(partial, "manifest.json.age")
          encrypt_bytes(JSON.generate(manifest), manifest_path)
          manifest_sha256 = BackupSet.sha256_file(manifest_path)
          key_fingerprint = BackupSet.authentication_key_fingerprint(authentication_key_bytes)
          marker = {
            "schema" => COMPLETE_SCHEMA,
            "manifest_sha256" => manifest_sha256,
            "authentication_key_fingerprint" => key_fingerprint,
            "authentication_hmac_sha256" => BackupSet.completion_authentication_hmac(
              authentication_key_bytes,
              manifest_sha256,
              key_fingerprint
            )
          }
          write_private(File.join(partial, "COMPLETE"), JSON.generate(marker))
          File.rename(partial, destination)
          @partial = nil
          manifest
        rescue SystemCallError => error
          raise Error.new("backup output could not be created", exit_code: 74), cause: error
        ensure
          authentication_key_bytes&.clear
          FileUtils.rm_rf(partial) if partial && File.exist?(partial)
        end

        private

        attr_reader :storage_root, :destination, :recipient, :configuration, :secret_bundle,
          :compose_contract_path, :authentication_key_path, :image, :predecessor, :s3_evidence_path,
          :age, :tar, :now, :partial, :authentication_key_bytes

        def validate!
          BackupSet.validate_image!(image)
          BackupSet.validate_predecessor!(predecessor, image)
          unless recipient.instance_of?(String) && recipient.bytesize.between?(4, 4096) && !recipient.match?(/[[:space:][:cntrl:]]/)
            raise Error, "age recipient is invalid"
          end
          BackupSet.validate_safe_tree!(storage_root, description: "storage volume")
          BackupSet.validate_regular_file!(configuration, description: "configuration", restrictive: true)
          BackupSet.validate_safe_tree!(secret_bundle, description: "secret bundle", restrictive: true)
          BackupSet.validate_regular_file!(compose_contract_path, description: "Compose contract", restrictive: true)
          @authentication_key_bytes = BackupSet.read_authentication_key(authentication_key_path)
          validate_destination!
          canonical = BackupSet.validate_backup_path_relationships!(
            storage_root:,
            destination:,
            configuration:,
            secret_bundle:
          )
          @storage_root = canonical.fetch(:storage_root)
          @destination = canonical.fetch(:destination)
          @configuration = canonical.fetch(:configuration)
          @secret_bundle = canonical.fetch(:secret_bundle)
          canonical_authentication_key = File.realpath(authentication_key_path)
          if BackupSet.same_or_within?(canonical_authentication_key, @storage_root) ||
              BackupSet.same_or_within?(canonical_authentication_key, @secret_bundle) ||
              canonical_authentication_key == @configuration ||
              canonical_authentication_key == File.realpath(compose_contract_path) ||
              (s3_evidence_path && File.exist?(s3_evidence_path) &&
                canonical_authentication_key == File.realpath(s3_evidence_path))
            raise Error, "backup authentication key must be outside archived inputs"
          end
          @authentication_key_path = canonical_authentication_key
          validate_configuration!
          compose_contract = validate_compose_contract!

          inspection = DatabaseInspector.new(storage_root).inspect!
          service = inspection.fetch("installation").fetch("storage_service")
          if service == "self_hosted_s3"
            raise Error.new("S3 backup evidence is required", exit_code: 69) unless s3_evidence_path
            BackupSet.validate_regular_file!(s3_evidence_path, description: "S3 backup evidence", restrictive: true)
            evidence = S3Evidence.load!(
              s3_evidence_path,
              installation: inspection.fetch("installation"),
              blobs: inspection.fetch("blobs"),
              recipient_fingerprint: BackupSet.recipient_fingerprint(recipient),
              now:,
              enforce_freshness: true
            )
            versions = evidence.fetch("objects").to_h { |object| [ [ object["service"], object["key"] ], object["version"] ] }
            inspection.fetch("blobs").each do |blob|
              blob["version"] = versions.fetch([ blob["service"], blob["key"] ])
            end
          elsif s3_evidence_path
            raise Error, "S3 backup evidence cannot be used with local storage"
          end
          inspection.merge("compose_contract" => compose_contract)
        end

        def validate_destination!
          raise Error.new("backup destination must be an explicit absolute path", exit_code: 64) unless Pathname.new(destination).absolute?
          raise Error.new("backup destination already exists", exit_code: 73) if File.exist?(destination) || File.symlink?(destination)

          parent = File.dirname(destination)
          canonical_parent = BackupSet.canonical_existing_directory(parent, description: "backup destination parent")
          canonical_storage = BackupSet.canonical_existing_directory(storage_root, description: "storage volume")
          @destination = File.join(canonical_parent, File.basename(destination))
          if BackupSet.same_or_within?(@destination, canonical_storage)
            raise Error.new("backup destination must be outside the storage volume", exit_code: 73)
          end
        rescue Errno::ENOENT, Errno::EACCES
          raise Error.new("backup destination parent is unavailable", exit_code: 73)
        end

        def validate_configuration!
          File.foreach(configuration) do |line|
            line = line.chomp
            next if line.match?(/\A\s*(?:#|\z)/)

            match = line.match(/\A\s*([A-Z][A-Z0-9_]*)\s*=\s*(.*)\z/)
            raise Error, "configuration contains an invalid assignment" unless match

            name = match[1]
            value = match[2]
            secret_name = name.match?(/(?:SECRET_KEY_BASE|TOKEN|PASSWORD|CLIENT_SECRET|ACCESS_KEY_ID|SECRET_ACCESS_KEY|API_KEY|RAILS_MASTER_KEY)/)
            if secret_name && !name.end_with?("_PATH", "_FILE") && !value.empty?
              raise Error, "configuration contains a raw secret assignment"
            end
          end
        end

        def validate_compose_contract!
          value = BackupSet.secure_json(compose_contract_path)
          BackupSet.validate_compose_contract!(value)
        end

        def create_partial!
          candidate = File.join(
            File.dirname(destination),
            ".#{File.basename(destination)}.partial-#{Process.pid}-#{SecureRandom.hex(8)}"
          )
          Dir.mkdir(candidate, 0o700)
          @partial = candidate
        end

        def encrypt_tar(root, filename)
          output = File.join(partial, filename)
          command = [
            tar, "--create", "--file", "-", "--format=pax", "--numeric-owner",
            "--directory", File.dirname(root), "--", File.basename(root)
          ]
          encrypt_command(command, output)
          artifact(output, filename)
        end

        def encrypt_file(path, filename)
          output = File.join(partial, filename)
          File.open(path, "rb") { |input| encrypt_io(input, output) }
          artifact(output, filename).merge("plaintext_sha256" => BackupSet.sha256_file(path))
        end

        def encrypt_bytes(bytes, output)
          raise Error, "manifest is too large" if bytes.bytesize > MAX_JSON_BYTES

          encrypt_io(StringIO.new(bytes.b), output)
        end

        def encrypt_command(command, output)
          Open3.popen3(*command) do |command_in, command_out, command_err, command_wait|
            command_in.close
            encrypt_io(command_out, output)
            error = command_err.read(4096).to_s
            raise Error, "backup archive creation failed" unless command_wait.value.success?
            raise Error, "backup archive creation failed" unless error.empty?
          end
        rescue Errno::ENOENT
          raise Error.new("required backup command is unavailable", exit_code: 69)
        end

        def encrypt_io(input, output)
          partial_output = "#{output}.partial"
          Tempfile.create("screenote-age-recipient") do |recipients_file|
            recipients_file.chmod(0o600)
            recipients_file.write("#{recipient}\n")
            recipients_file.flush
            Open3.popen3(age, "--encrypt", "--recipients-file", recipients_file.path) do |age_in, age_out, age_err, age_wait|
              error_reader = Thread.new { age_err.read(4096) }
              output_writer = Thread.new do
                File.open(partial_output, File::WRONLY | File::CREAT | File::EXCL, 0o600) do |ciphertext|
                  IO.copy_stream(age_out, ciphertext)
                  ciphertext.flush
                  ciphertext.fsync
                end
              end
              IO.copy_stream(input, age_in)
              age_in.close
              output_writer.value
              error_reader.value
              raise Error, "age encryption failed" unless age_wait.value.success?
            end
          end
          File.rename(partial_output, output)
        rescue Errno::ENOENT
          raise Error.new("age is unavailable", exit_code: 69)
        ensure
          FileUtils.rm_f(partial_output) if defined?(partial_output) && partial_output
        end

        def artifact(path, filename)
          { "file" => filename, "sha256" => BackupSet.sha256_file(path), "byte_size" => File.size(path) }
        end

        def build_manifest(inspection, artifacts)
          installation = inspection.fetch("installation")
          {
            "schema" => SCHEMA,
            "finalized" => true,
            "created_at" => now.iso8601,
            "restore_image" => image,
            "predecessor" => predecessor,
            "age_recipient_fingerprint" => BackupSet.recipient_fingerprint(recipient),
            "configuration_fingerprint" => BackupSet.sha256_file(configuration),
            "storage_service" => installation.fetch("storage_service"),
            "storage_namespace_fingerprint" => installation.fetch("storage_namespace_fingerprint"),
            "database_roles" => inspection.fetch("databases"),
            "blobs" => inspection.fetch("blobs"),
            "artifacts" => artifacts,
            "compose_contract" => inspection.fetch("compose_contract")
          }
        end

        def write_private(path, bytes)
          File.open(path, File::WRONLY | File::CREAT | File::EXCL, 0o600) { |file| file.write(bytes) }
        end
      end

      class Restorer
        MANIFEST_KEYS = Creator::MANIFEST_KEYS
        DATABASE_ROLE_KEYS = %w[file schema_version].freeze
        BASE_ARTIFACT_KEYS = %w[file sha256 byte_size].freeze
        PLAINTEXT_ARTIFACT_KEYS = (BASE_ARTIFACT_KEYS + %w[plaintext_sha256]).freeze

        def initialize(source:, identity:, storage_root:, operator_destination:, compose_contract:,
          authentication_key:, image:, predecessor:, age: ENV.fetch("SCREENOTE_AGE_BIN", "age"),
          tar: ENV.fetch("SCREENOTE_TAR_BIN", "tar"))
          @source = File.expand_path(source)
          @identity = File.expand_path(identity)
          @storage_root = File.expand_path(storage_root)
          @operator_destination = File.expand_path(operator_destination)
          @compose_contract_path = File.expand_path(compose_contract)
          @authentication_key_path = File.expand_path(authentication_key)
          @image = image
          @predecessor = predecessor
          @age = age
          @tar = tar
          @volume_staging = nil
          @operator_staging = nil
          @backup_source = nil
          @identity_io = nil
          @identity_descriptor_path = nil
          @compose_contract_snapshot = nil
        end

        def call
          preflight!
          create_staging!
          snapshot_inputs!
          manifest = validate_snapshot!
          @validated_manifest = manifest
          volume_archive_root = extract_archive("volume", File.join(volume_staging, "archive"))
          secret_archive_root = extract_archive("secrets", File.join(operator_staging, "secret-archive"))
          decrypt_configuration!(manifest)
          validate_restored!(manifest, volume_archive_root)
          publish_all!(volume_archive_root, secret_archive_root)
          manifest
        rescue SystemCallError => error
          raise Error.new("restore could not be completed", exit_code: 74), cause: error
        ensure
          identity_io&.close unless identity_io&.closed?
          FileUtils.rm_rf(volume_staging) if volume_staging && File.exist?(volume_staging)
          FileUtils.rm_rf(operator_staging) if operator_staging && File.exist?(operator_staging)
        end

        private

        attr_reader :source, :identity, :storage_root, :operator_destination,
          :compose_contract_path, :authentication_key_path, :image, :predecessor, :age, :tar,
          :volume_staging, :operator_staging, :backup_source, :identity_io,
          :identity_descriptor_path, :compose_contract_snapshot

        def preflight!
          BackupSet.validate_image!(image)
          BackupSet.validate_predecessor!(predecessor, image)
          BackupSet.validate_safe_tree!(source, description: "backup set", restrictive: true)
          BackupSet.validate_regular_file!(identity, description: "age identity", restrictive: true)
          validate_authentication_key!
          BackupSet.validate_regular_file!(compose_contract_path, description: "Compose contract", restrictive: true)
          validate_empty_directory!(storage_root, "restore volume")
          validate_empty_directory!(operator_destination, "operator destination")
          validate_output_files!(source)
          canonicalize_and_validate_paths!
        end

        def validate_authentication_key!
          key = BackupSet.read_authentication_key(authentication_key_path)
        ensure
          key&.clear
        end

        def validate_snapshot!
          validate_output_files!(backup_source)

          BackupSet.authenticate_completion!(source: backup_source, authentication_key: authentication_key_path)
          manifest_path = File.join(backup_source, "manifest.json.age")

          manifest = parse_manifest(decrypt_bytes(manifest_path, maximum: MAX_JSON_BYTES))
          raise Error, "restore image does not match the backup set" unless manifest["restore_image"] == image
          raise Error, "predecessor does not match the backup set" unless manifest["predecessor"] == predecessor
          compose = BackupSet.validate_compose_contract!(BackupSet.secure_json(compose_contract_snapshot))
          raise Error, "Compose contract does not match the backup set" unless compose == manifest["compose_contract"]
          validate_artifacts!(manifest)
          manifest
        rescue Error => error
          raise error if error.message.match?(/restore image|predecessor|restore volume|operator destination|Compose contract/)

          raise Error.new("backup set is invalid", exit_code: error.exit_code), cause: error
        end

        def validate_empty_directory!(path, description)
          stat = File.lstat(path)
          unless stat.directory? && !stat.symlink? && Dir.empty?(path)
            raise Error.new("#{description} must be empty", exit_code: 73)
          end
        rescue Errno::ENOENT, Errno::EACCES
          raise Error.new("#{description} must be an existing empty directory", exit_code: 73)
        end

        def canonicalize_and_validate_paths!
          @source = BackupSet.canonical_existing_directory(source, description: "backup set")
          @storage_root = BackupSet.canonical_existing_directory(storage_root, description: "restore volume")
          @operator_destination = BackupSet.canonical_existing_directory(
            operator_destination,
            description: "operator destination"
          )
          paths = [ @source, @storage_root, @operator_destination ]
          paths.combination(2) do |left, right|
            if same_or_within?(left, right) || same_or_within?(right, left)
              raise Error.new("backup and restore paths must not overlap", exit_code: 73)
            end
          end
        end

        def same_or_within?(candidate, root)
          candidate == root || candidate.start_with?("#{root}/")
        end

        def validate_output_files!(root)
          entries = Dir.children(root).sort
          valid = entries == OUTPUT_FILES || entries == (OUTPUT_FILES + [ S3_OUTPUT_FILE ]).sort
          raise Error, "backup set contains missing or unexpected files" unless valid
        end

        def parse_manifest(bytes)
          raise Error, "manifest is too large" if bytes.bytesize > MAX_JSON_BYTES
          manifest = JSON.parse(bytes)
          raise Error, "manifest is invalid" unless manifest.instance_of?(Hash)
          BackupSet.validate_exact_keys!(manifest, MANIFEST_KEYS, "manifest")
          raise Error, "manifest schema is unsupported" unless manifest["schema"] == SCHEMA
          raise Error, "manifest is unfinalized" unless manifest["finalized"] == true
          Time.iso8601(manifest.fetch("created_at"))
          BackupSet.validate_image!(manifest["restore_image"], name: "manifest restore image")
          BackupSet.validate_predecessor!(manifest["predecessor"], manifest["restore_image"])
          unless manifest["age_recipient_fingerprint"]&.match?(DIGEST_PATTERN) &&
              manifest["configuration_fingerprint"]&.match?(DIGEST_PATTERN) &&
              manifest["storage_namespace_fingerprint"]&.match?(DIGEST_PATTERN)
            raise Error, "manifest fingerprints are invalid"
          end
          unless %w[self_hosted_local self_hosted_s3].include?(manifest["storage_service"])
            raise Error, "manifest storage service is invalid"
          end
          validate_database_roles!(manifest["database_roles"])
          validate_manifest_blobs!(manifest["blobs"], manifest["storage_service"])
          BackupSet.validate_compose_contract!(manifest["compose_contract"])
          manifest
        rescue JSON::ParserError, KeyError, ArgumentError, TypeError
          raise Error, "manifest is invalid"
        end

        def validate_artifacts!(manifest)
          artifacts = manifest["artifacts"]
          raise Error, "manifest artifacts are invalid" unless artifacts.instance_of?(Hash)
          expected = %w[configuration secrets volume]
          expected << "s3_evidence" if manifest["storage_service"] == "self_hosted_s3"
          raise Error, "manifest artifact set is invalid" unless artifacts.keys.sort == expected.sort

          artifacts.each do |name, artifact|
            expected_keys = %w[configuration s3_evidence].include?(name) ? PLAINTEXT_ARTIFACT_KEYS : BASE_ARTIFACT_KEYS
            unless artifact.instance_of?(Hash)
              raise Error, "manifest artifact is invalid"
            end
            BackupSet.validate_exact_keys!(artifact, expected_keys, "manifest artifact")
            unless artifact["file"] == ARTIFACT_FILES.fetch(name) &&
                artifact["sha256"]&.match?(DIGEST_PATTERN) &&
                artifact["byte_size"].is_a?(Integer) && artifact["byte_size"].positive? &&
                (!artifact.key?("plaintext_sha256") || artifact["plaintext_sha256"]&.match?(DIGEST_PATTERN))
              raise Error, "manifest artifact is invalid"
            end
            path = File.join(backup_source, artifact.fetch("file"))
            BackupSet.validate_regular_file!(path, description: "backup artifact", restrictive: true)
            unless File.size(path) == artifact["byte_size"] && BackupSet.sha256_file(path) == artifact["sha256"]
              raise Error, "backup artifact checksum does not match"
            end
          end
          configuration = artifacts.fetch("configuration")
          unless configuration.fetch("plaintext_sha256") == manifest.fetch("configuration_fingerprint")
            raise Error, "configuration fingerprint does not match"
          end
          has_s3_file = File.exist?(File.join(backup_source, S3_OUTPUT_FILE))
          raise Error, "manifest S3 artifact set is invalid" unless has_s3_file == (manifest["storage_service"] == "self_hosted_s3")
        end

        def validate_database_roles!(roles)
          unless roles.instance_of?(Hash) && roles.keys.sort == DATABASE_ROLES.sort
            raise Error, "manifest database roles are invalid"
          end
          roles.each do |role, details|
            unless details.instance_of?(Hash)
              raise Error, "manifest database role is invalid"
            end
            BackupSet.validate_exact_keys!(details, DATABASE_ROLE_KEYS, "manifest database role")
            unless details["file"] == "#{role}.sqlite3" && details["schema_version"]&.match?(SCHEMA_VERSION_PATTERN)
              raise Error, "manifest database role is invalid"
            end
          end
        end

        def validate_manifest_blobs!(blobs, storage_service)
          raise Error, "manifest blob inventory is invalid" unless blobs.instance_of?(Array)

          blobs.each do |blob|
            raise Error, "manifest blob inventory is invalid" unless blob.instance_of?(Hash)

            BackupSet.validate_blob_fields!(blob, expected_service: storage_service)
            version = blob["version"]
            valid_version = if storage_service == "self_hosted_local"
              version.is_a?(String) && version.match?(DIGEST_PATTERN)
            else
              version.is_a?(String) && version.match?(/\A[A-Za-z0-9._:+\/-]{1,512}\z/)
            end
            raise Error, "manifest blob version is invalid" unless valid_version
          end
          canonical = BackupSet.canonical_object_inventory(blobs)
          raise Error, "manifest blob inventory must be canonical and unique" unless blobs == canonical
          unless blobs.map { |blob| [ blob["service"], blob["key"] ] }.uniq.length == blobs.length
            raise Error, "manifest blob inventory contains duplicates"
          end
        end

        def create_staging!
          @volume_staging = File.join(storage_root, ".screenote-restore-#{SecureRandom.hex(8)}")
          @operator_staging = File.join(operator_destination, ".screenote-restore-#{SecureRandom.hex(8)}")
          Dir.mkdir(volume_staging, 0o700)
          Dir.mkdir(operator_staging, 0o700)
        end

        def snapshot_inputs!
          open_identity_descriptor!
          @backup_source = File.join(operator_staging, "backup-set")
          Dir.mkdir(backup_source, 0o700)
          Dir.children(source).sort.each do |entry|
            copy_regular_file!(File.join(source, entry), File.join(backup_source, entry), "backup set input")
          end
          @compose_contract_snapshot = File.join(operator_staging, "compose-contract.json")
          copy_regular_file!(compose_contract_path, compose_contract_snapshot, "Compose contract")
        end

        def open_identity_descriptor!
          @identity_io = File.open(identity, File::RDONLY | File::NOFOLLOW)
          stat = identity_io.stat
          unless stat.file? && stat.uid == Process.uid && (stat.mode & 0o077).zero?
            raise Error, "age identity changed during restore preflight"
          end

          identity_io.close_on_exec = true
          descriptor_root = [ "/proc/self/fd", "/dev/fd" ].find { |path| File.directory?(path) }
          raise Error.new("stable age identity descriptors are unavailable", exit_code: 69) unless descriptor_root

          @identity_descriptor_path = File.join(descriptor_root, identity_io.fileno.to_s)
        rescue Errno::ELOOP, Errno::ENOENT, Errno::EACCES
          raise Error, "age identity changed during restore preflight"
        end

        def copy_regular_file!(source_path, destination_path, description, mode: 0o600)
          File.open(source_path, File::RDONLY | File::NOFOLLOW) do |input|
            stat = input.stat
            unless stat.file? && stat.uid == Process.uid
              raise Error, "#{description} changed during restore preflight"
            end
            File.open(destination_path, File::WRONLY | File::CREAT | File::EXCL, mode) do |output|
              IO.copy_stream(input, output)
              output.flush
              output.fsync
            end
          end
        rescue Errno::ELOOP, Errno::ENOENT, Errno::EACCES
          raise Error, "#{description} changed during restore preflight"
        end

        def extract_archive(name, staging)
          Dir.mkdir(staging, 0o700)
          artifact = manifest_artifact(name)
          encrypted_path = verified_artifact_path(name)
          names, types = archive_listing(encrypted_path)
          validate_archive_listing!(names, types)
          decrypt_to_tar(encrypted_path, [ tar, "--extract", "--file", "-", "--directory", staging,
            "--no-same-owner", "--same-permissions" ])
          verify_artifact_file!(encrypted_path, artifact)
          roots = Dir.children(staging)
          raise Error, "backup archive root is invalid" unless roots.one?
          root = File.join(staging, roots.first)
          BackupSet.validate_safe_tree!(root, description: "restored archive")
          root
        end

        def manifest_artifact(name)
          @validated_manifest.fetch("artifacts").fetch(name)
        end

        def archive_listing(path)
          names = decrypt_to_tar(path, [ tar, "--list", "--file", "-" ], maximum_output: MAX_JSON_BYTES).lines(chomp: true)
          verbose = decrypt_to_tar(
            path,
            [ tar, "--list", "--verbose", "--file", "-" ],
            maximum_output: MAX_JSON_BYTES
          ).lines(chomp: true)
          [ names, verbose.map { |line| line[0] } ]
        end

        def validate_archive_listing!(names, types)
          raise Error, "backup archive is empty" if names.empty?
          raise Error, "backup archive entry types are invalid" unless names.length == types.length && types.all? { |type| %w[- d].include?(type) }
          roots = names.map { |name| Pathname.new(name).each_filename.first }.uniq
          raise Error, "backup archive root is invalid" unless roots.one?
          names.each do |name|
            path = Pathname.new(name)
            if name.bytesize > 4096 || path.absolute? ||
                path.each_filename.any? { |component| %w[. ..].include?(component) } ||
                name.match?(/[\u0000-\u001f\u007f]/)
              raise Error, "backup archive path is unsafe"
            end
          end
        end

        def decrypt_to_tar(encrypted_path, tar_command, maximum_output: 1024 * 1024)
          output = +""
          with_age_decryption(encrypted_path) do |age_in, age_out, age_err, age_wait|
            age_in.close
            age_error = Thread.new { age_err.read(4096) }
            Open3.popen3(*tar_command, close_others: true) do |tar_in, tar_out, tar_err, tar_wait|
              copy = Thread.new do
                IO.copy_stream(age_out, tar_in)
              ensure
                tar_in.close
              end
              output_reader = Thread.new { read_limited(tar_out, maximum_output) }
              tar_error = Thread.new { tar_err.read(4096) }
              copy.value
              output = output_reader.value
              tar_error.value
              raise Error, "backup archive is invalid" unless tar_wait.value.success?
            end
            age_error.value
            raise Error, "backup archive authentication failed" unless age_wait.value.success?
          end
          output
        rescue Errno::ENOENT
          raise Error.new("required restore command is unavailable", exit_code: 69)
        end

        def with_age_decryption(encrypted_path, &block)
          identity_io.rewind
          spawn_options = { identity_io.fileno => identity_io, close_others: true }
          Open3.popen3(
            age,
            "--decrypt",
            "--identity",
            identity_descriptor_path,
            encrypted_path,
            spawn_options,
            &block
          )
        end

        def decrypt_configuration!(manifest)
          artifact = manifest.fetch("artifacts").fetch("configuration")
          path = verified_artifact_path("configuration")
          bytes = decrypt_bytes(path, maximum: MAX_JSON_BYTES)
          verify_artifact_file!(path, artifact)
          unless Digest::SHA256.hexdigest(bytes) == artifact["plaintext_sha256"] &&
              Digest::SHA256.hexdigest(bytes) == manifest["configuration_fingerprint"]
            raise Error, "configuration fingerprint does not match"
          end
          File.open(File.join(operator_staging, ".env"), File::WRONLY | File::CREAT | File::EXCL, 0o600) do |file|
            file.write(bytes)
          end
        end

        def decrypt_bytes(path, maximum:)
          stat = BackupSet.validate_regular_file!(path, description: "encrypted backup artifact", restrictive: true)
          raise Error, "backup artifact is too large" if stat.size > maximum + MAX_AGE_OVERHEAD

          output = +""
          with_age_decryption(path) do |stdin, stdout, stderr, wait|
            stdin.close
            error_reader = Thread.new { stderr.read(4096) }
            begin
              output = read_limited(stdout, maximum)
            rescue Error
              Process.kill("TERM", wait.pid) if wait.alive?
              raise
            ensure
              stdout.close unless stdout.closed?
            end
            error_reader.value
            raise Error, "backup artifact authentication failed" unless wait.value.success?
          end
          output
        rescue Errno::ENOENT
          raise Error.new("age is unavailable", exit_code: 69)
        end

        def read_limited(io, maximum)
          output = +""
          loop do
            chunk = io.readpartial(64 * 1024)
            output << chunk
            raise Error, "backup artifact is too large" if output.bytesize > maximum
          end
        rescue EOFError
          output
        end

        def verified_artifact_path(name)
          artifact = manifest_artifact(name)
          path = File.join(backup_source, artifact.fetch("file"))
          verify_artifact_file!(path, artifact)
          path
        end

        def verify_artifact_file!(path, artifact)
          stat = BackupSet.validate_regular_file!(path, description: "backup artifact", restrictive: true)
          unless stat.size == artifact.fetch("byte_size") && BackupSet.sha256_file(path) == artifact.fetch("sha256")
            raise Error, "backup artifact checksum does not match"
          end
        end

        def validate_restored!(manifest, volume_root)
          @validated_manifest = manifest
          inspection = DatabaseInspector.new(volume_root).inspect!
          unless inspection.fetch("databases") == manifest.fetch("database_roles")
            raise Error, "restored database schema does not match the manifest"
          end
          installation = inspection.fetch("installation")
          unless installation.fetch("storage_service") == manifest.fetch("storage_service") &&
              installation.fetch("storage_namespace_fingerprint") == manifest.fetch("storage_namespace_fingerprint")
            raise Error, "restored storage identity does not match the manifest"
          end

          if manifest.fetch("storage_service") == "self_hosted_local"
            raise Error, "restored local blob inventory does not match the manifest" unless inspection.fetch("blobs") == manifest.fetch("blobs")
          else
            evidence_artifact = manifest.fetch("artifacts").fetch("s3_evidence")
            evidence_path = verified_artifact_path("s3_evidence")
            evidence_bytes = decrypt_bytes(evidence_path, maximum: MAX_JSON_BYTES)
            verify_artifact_file!(evidence_path, evidence_artifact)
            unless Digest::SHA256.hexdigest(evidence_bytes) == evidence_artifact.fetch("plaintext_sha256")
              raise Error, "S3 evidence fingerprint does not match"
            end
            evidence_file = File.join(operator_staging, ".s3-evidence.json")
            File.open(evidence_file, File::WRONLY | File::CREAT | File::EXCL, 0o600) { |file| file.write(evidence_bytes) }
            evidence = S3Evidence.load!(
              evidence_file,
              installation:,
              blobs: inspection.fetch("blobs"),
              recipient_fingerprint: manifest.fetch("age_recipient_fingerprint")
            )
            versions = evidence.fetch("objects").to_h do |object|
              [ [ object.fetch("service"), object.fetch("key") ], object.fetch("version") ]
            end
            restored_blobs = inspection.fetch("blobs").map do |blob|
              blob.merge("version" => versions.fetch([ blob.fetch("service"), blob.fetch("key") ]))
            end
            unless restored_blobs == manifest.fetch("blobs")
              raise Error, "restored S3 blob inventory does not match the manifest"
            end
            FileUtils.rm_f(evidence_file)
          end
        end

        def publish_all!(volume_root, secret_root)
          moves = Dir.children(volume_root).sort.map do |entry|
            [ File.join(volume_root, entry), File.join(storage_root, entry) ]
          end
          moves << [ secret_root, File.join(operator_destination, "secrets") ]
          moves << [ File.join(operator_staging, ".env"), File.join(operator_destination, ".env") ]

          completed = []
          moves.each do |source_path, destination_path|
            raise Error, "restore destination changed during publication" if File.exist?(destination_path) || File.symlink?(destination_path)

            File.rename(source_path, destination_path)
            completed << [ source_path, destination_path ]
          end
        rescue StandardError => error
          rollback_failed = false
          completed.reverse_each do |source_path, destination_path|
            begin
              File.rename(destination_path, source_path) if File.exist?(destination_path) || File.symlink?(destination_path)
            rescue SystemCallError
              rollback_failed = true
            end
          end
          mark_failed_restore! if rollback_failed
          raise error
        end

        def mark_failed_restore!
          [ storage_root, operator_destination ].each do |root|
            path = File.join(root, ".screenote-restore-failed")
            File.open(path, File::WRONLY | File::CREAT | File::EXCL, 0o600) do |file|
              file.write("restore publication rollback failed; inspect this target before reuse\n")
            end
          rescue SystemCallError
            nil
          end
        end
      end
    end
  end
end
