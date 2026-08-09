# frozen_string_literal: true

# screenote-edition: self_hosted

require "test_helper"
require "digest"
require "fileutils"
require "open3"
require "rbconfig"
require "shellwords"
require "tmpdir"
require "yaml"

class SelfHostedSecretConfigurationTest < ActiveSupport::TestCase
  ENTRYPOINT = Rails.root.join("bin/docker-entrypoint").to_s.freeze
  BASE_COMPOSE = Rails.root.join("compose.yaml").freeze
  BOOTSTRAP_COMPOSE = Rails.root.join("compose.bootstrap.yaml").freeze
  S3_COMPOSE = Rails.root.join("compose.s3.yaml").freeze
  OPTIONAL_PROVIDER_COMPOSE = {
    smtp: Rails.root.join("compose.smtp.yaml"),
    google_oauth: Rails.root.join("compose.google-oauth.yaml"),
    github_oauth: Rails.root.join("compose.github-oauth.yaml"),
    honeybadger: Rails.root.join("compose.honeybadger.yaml")
  }.freeze
  FILE_BACKED_SECRET_NAMES = %w[
    SECRET_KEY_BASE
    SCREENOTE_AUTHENTICATION_LINK_PRIOR_KEYS
    SCREENOTE_BOOTSTRAP_TOKEN
    SCREENOTE_S3_ACCESS_KEY_ID
    SCREENOTE_S3_SECRET_ACCESS_KEY
    SMTP_PASSWORD
    GOOGLE_CLIENT_SECRET
    GITHUB_CLIENT_SECRET
    HONEYBADGER_API_KEY
    HONEYBADGER_JS_API_KEY
  ].freeze

  test "entrypoint loads a restricted secret without printing it or retaining its path variable" do
    secret = "entrypoint-secret-#{'a' * 48}"

    with_secret_file(secret, mode: 0o400) do |path|
      stdout, stderr, status = run_entrypoint(
        { "SECRET_KEY_BASE_FILE" => path },
        RbConfig.ruby, "-e",
        'print [ENV.fetch("SECRET_KEY_BASE").bytesize, ENV.key?("SECRET_KEY_BASE_FILE")].join(":")'
      )

      assert status.success?, stderr
      assert_equal "#{secret.bytesize}:false", stdout
      assert_not_includes stderr, secret
    end
  end

  test "entrypoint rejects missing and broadly readable secret files" do
    missing_path = Rails.root.join("tmp/missing-screenote-secret").to_s
    _stdout, stderr, status = run_entrypoint(
      { "SECRET_KEY_BASE_FILE" => missing_path },
      RbConfig.ruby, "-e", "exit"
    )

    assert_not status.success?
    assert_includes stderr, "regular, non-symlink file"
    assert_includes stderr, missing_path

    with_secret_file("b" * 64, mode: 0o440) do |path|
      _stdout, stderr, status = run_entrypoint(
        { "SECRET_KEY_BASE_FILE" => path },
        RbConfig.ruby, "-e", "exit"
      )

      assert_not status.success?
      assert_includes stderr, "must not grant group or other permissions"
      assert_not_includes stderr, "b" * 64
    end
  end

  test "entrypoint prepares databases and installation before starting the server" do
    Dir.mktmpdir("screenote-entrypoint") do |directory|
      trace = File.join(directory, "trace")
      write_executable(
        File.join(directory, "bin/screenote-deployment-preflight"),
        <<~'BASH'
          #!/usr/bin/env bash
          printf 'preflight\n' >> "$SCREENOTE_TEST_TRACE"
        BASH
      )
      write_executable(
        File.join(directory, "bin/rails"),
        <<~'BASH'
          #!/usr/bin/env bash
          printf 'rails:%s\n' "$*" >> "$SCREENOTE_TEST_TRACE"
        BASH
      )
      write_executable(
        File.join(directory, "bin/thrust"),
        <<~'BASH'
          #!/usr/bin/env bash
          printf 'thrust:%s bootstrap=%s\n' "$*" "${SCREENOTE_BOOTSTRAP_TOKEN-unset}" >> "$SCREENOTE_TEST_TRACE"
        BASH
      )

      _stdout, stderr, status = run_entrypoint(
        {
          "SCREENOTE_EDITION" => "saas",
          "SCREENOTE_BOOTSTRAP_TOKEN" => "must-not-reach-server",
          "SCREENOTE_TEST_TRACE" => trace
        },
        "./bin/thrust", "./bin/rails", "server",
        chdir: directory
      )

      assert status.success?, stderr
      assert_equal(
        [
          "preflight",
          "rails:runner script/saas_deploy_guard",
          "rails:db:prepare",
          "rails:runner Installations::Prepare.call",
          "rails:runner AuthenticationLinks::KeyringPreflight.call",
          "rails:runner ReconcileScreenshotProcessingJob.enqueue_for_startup!",
          "thrust:./bin/rails server bootstrap=unset"
        ],
        File.readlines(trace, chomp: true)
      )
    end
  end

  test "entrypoint refuses to serve when startup reconciliation cannot be enqueued" do
    Dir.mktmpdir("screenote-entrypoint-enqueue-failure") do |directory|
      trace = File.join(directory, "trace")
      write_executable(
        File.join(directory, "bin/screenote-deployment-preflight"),
        "#!/usr/bin/env bash\nprintf 'preflight\\n' >> \"$SCREENOTE_TEST_TRACE\"\n"
      )
      write_executable(
        File.join(directory, "bin/rails"),
        <<~'BASH'
          #!/usr/bin/env bash
          printf 'rails:%s\n' "$*" >> "$SCREENOTE_TEST_TRACE"
          [[ "$*" != "runner ReconcileScreenshotProcessingJob.enqueue_for_startup!" ]]
        BASH
      )
      write_executable(
        File.join(directory, "bin/thrust"),
        <<~'BASH'
          #!/usr/bin/env bash
          printf 'thrust:%s\n' "$*" >> "$SCREENOTE_TEST_TRACE"
        BASH
      )

      _stdout, _stderr, status = run_entrypoint(
        {
          "SCREENOTE_EDITION" => "saas",
          "SCREENOTE_TEST_TRACE" => trace
        },
        "./bin/thrust", "./bin/rails", "server",
        chdir: directory
      )

      assert_not status.success?
      assert_equal(
        [
          "preflight",
          "rails:runner script/saas_deploy_guard",
          "rails:db:prepare",
          "rails:runner Installations::Prepare.call",
          "rails:runner AuthenticationLinks::KeyringPreflight.call",
          "rails:runner ReconcileScreenshotProcessingJob.enqueue_for_startup!"
        ],
        File.readlines(trace, chomp: true)
      )
    end
  end

  test "SaaS server startup cannot bypass a pending credential cutover" do
    Dir.mktmpdir("screenote-entrypoint-cutover") do |directory|
      trace = File.join(directory, "trace")
      write_executable(
        File.join(directory, "bin/screenote-deployment-preflight"),
        <<~'BASH'
          #!/usr/bin/env bash
          printf 'preflight\n' >> "$SCREENOTE_TEST_TRACE"
        BASH
      )
      write_executable(
        File.join(directory, "bin/rails"),
        <<~'BASH'
          #!/usr/bin/env bash
          printf 'rails:%s\n' "$*" >> "$SCREENOTE_TEST_TRACE"
          [[ "$*" != "runner script/saas_deploy_guard" ]]
        BASH
      )

      _stdout, stderr, status = run_entrypoint(
        {
          "SCREENOTE_EDITION" => "saas",
          "SCREENOTE_TEST_TRACE" => trace
        },
        "./bin/rails", "server",
        chdir: directory
      )

      assert_not status.success?
      assert_empty stderr
      assert_equal(
        [ "preflight", "rails:runner script/saas_deploy_guard" ],
        File.readlines(trace, chomp: true)
      )
    end
  end

  test "standalone deployment preflight activates production bundle gems" do
    source = Rails.root.join("bin/screenote-deployment-preflight").read

    assert_operator source.index('require "bundler/setup"'), :<,
      source.index('require_relative "../lib/screenote/deployment_preflight"')
  end

  test "entrypoint rejects a durable self hosted primary before SaaS database preparation" do
    Dir.mktmpdir("screenote-entrypoint-mode-drift") do |directory|
      storage_root = File.join(directory, "storage")
      FileUtils.mkdir_p(storage_root)
      primary_path = create_installation_primary(storage_root, deployment_mode: "self_hosted")
      primary_digest = Digest::SHA256.file(primary_path).hexdigest
      trace = File.join(directory, "trace")
      install_actual_preflight(directory, storage_root: storage_root)
      write_executable(
        File.join(directory, "bin/rails"),
        <<~'BASH'
          #!/usr/bin/env bash
          printf 'rails:%s\n' "$*" >> "$SCREENOTE_TEST_TRACE"
        BASH
      )

      sentinel = "postgres-password-must-not-leak"
      _stdout, stderr, status = run_entrypoint(
        {
          "SCREENOTE_EDITION" => "saas",
          "SCREENOTE_STORAGE_ROOT" => storage_root,
          "SCREENOTE_TEST_TRACE" => trace,
          "DATABASE_URL" => "postgres://screenote:#{sentinel}@unreachable.invalid/primary"
        },
        "./bin/rails", "server",
        chdir: directory
      )

      assert_not status.success?
      assert_includes stderr, "durable self-hosted primary"
      assert_includes stderr, "configured edition is saas"
      assert_not_includes stderr, sentinel
      assert_not File.exist?(trace), "db:prepare must not run after mode drift is detected"
      assert_equal primary_digest, Digest::SHA256.file(primary_path).hexdigest
    end
  end

  test "entrypoint rejects retained SaaS database settings before self hosted preparation" do
    Dir.mktmpdir("screenote-entrypoint-reverse-mode-drift") do |directory|
      storage_root = File.join(directory, "storage")
      FileUtils.mkdir_p(storage_root)
      trace = File.join(directory, "trace")
      install_actual_preflight(directory, storage_root: storage_root)
      write_executable(
        File.join(directory, "bin/rails"),
        <<~'BASH'
          #!/usr/bin/env bash
          printf 'rails:%s\n' "$*" >> "$SCREENOTE_TEST_TRACE"
        BASH
      )

      secret_path = File.join(directory, "secret_key_base")
      File.binwrite(secret_path, "#{'s' * 64}\n")
      File.chmod(0o400, secret_path)
      sentinel = "postgres-password-must-not-leak"

      _stdout, stderr, status = run_entrypoint(
        {
          "SCREENOTE_EDITION" => "self_hosted",
          "SCREENOTE_STORAGE_ROOT" => storage_root,
          "SCREENOTE_TEST_TRACE" => trace,
          "SECRET_KEY_BASE_FILE" => secret_path,
          "DATABASE_URL" => "postgres://screenote:#{sentinel}@unreachable.invalid/primary"
        },
        "./bin/rails", "server",
        chdir: directory
      )

      assert_not status.success?
      assert_includes stderr, "self-hosted startup cannot retain SaaS database settings"
      assert_includes stderr, "DATABASE_URL"
      assert_not_includes stderr, sentinel
      assert_not File.exist?(trace), "db:prepare must not run after topology drift is detected"
      assert_empty Dir.children(storage_root)
    end
  end

  test "entrypoint rejects bootstrap drift before a pending migration can mutate the primary" do
    Dir.mktmpdir("screenote-entrypoint-bootstrap-drift") do |directory|
      storage_root = File.join(directory, "storage")
      FileUtils.mkdir_p(storage_root)
      persisted_environment = {
        "SCREENOTE_EDITION" => "self_hosted",
        "SCREENOTE_BASE_URL" => "http://screenote.internal:3005",
        "SECRET_KEY_BASE" => "s" * 64,
        "SCREENOTE_BOOTSTRAP_TOKEN" => "b" * 43
      }
      primary_path = create_self_hosted_identity_primary(storage_root, environment: persisted_environment)
      primary_digest = Digest::SHA256.file(primary_path).hexdigest
      trace = File.join(directory, "trace")
      install_actual_preflight(directory, storage_root: storage_root)
      write_executable(
        File.join(directory, "bin/rails"),
        <<~'BASH'
          #!/usr/bin/env bash
          printf 'rails:%s\n' "$*" >> "$SCREENOTE_TEST_TRACE"
        BASH
      )

      with_secret_file("s" * 64, mode: 0o400) do |secret_key_path|
        with_secret_file("c" * 43, mode: 0o400) do |bootstrap_path|
          _stdout, stderr, status = run_entrypoint(
            {
              "SCREENOTE_EDITION" => "self_hosted",
              "SCREENOTE_BASE_URL" => "http://screenote.internal:3005",
              "SCREENOTE_STORAGE_ROOT" => storage_root,
              "SCREENOTE_TEST_TRACE" => trace,
              "SECRET_KEY_BASE_FILE" => secret_key_path,
              "SCREENOTE_BOOTSTRAP_TOKEN_FILE" => bootstrap_path
            },
            "./bin/rails", "server",
            chdir: directory
          )

          assert_not status.success?
          assert_includes stderr, "bootstrap material differs"
          assert_not File.exist?(trace), "db:prepare must not run after bootstrap drift is detected"
          assert_equal primary_digest, Digest::SHA256.file(primary_path).hexdigest
        end
      end
    end
  end

  test "server process receives direct and file backed secrets without bootstrap material" do
    Dir.mktmpdir("screenote-entrypoint") do |directory|
      write_executable(
        File.join(directory, "bin/screenote-deployment-preflight"),
        "#!/usr/bin/env bash\nexit 0\n"
      )
      write_executable(File.join(directory, "bin/rails"), "#!/usr/bin/env bash\nexit 0\n")
      write_executable(
        File.join(directory, "bin/thrust"),
        <<~'BASH'
          #!/usr/bin/env bash
          set -Eeuo pipefail
          [[ "${SECRET_KEY_BASE-}" == "${SCREENOTE_TEST_EXPECTED_SECRET-}" ]] || {
            printf 'secret mismatch\n' >&2
            exit 1
          }
          [[ -z "${SECRET_KEY_BASE_FILE+x}" ]] || {
            printf 'secret file variable retained\n' >&2
            exit 1
          }
          [[ -z "${SCREENOTE_BOOTSTRAP_TOKEN+x}" ]] || {
            printf 'bootstrap material retained\n' >&2
            exit 1
          }
          printf 'secret=matched bootstrap=absent secret_file=absent\n' > "$SCREENOTE_TEST_TRACE"
        BASH
      )

      direct_secret = "direct-secret-#{'s' * 48}"
      assert_server_receives_secret(
        directory: directory,
        secret: direct_secret,
        environment: { "SECRET_KEY_BASE" => direct_secret }
      )

      file_secret = "file-secret-#{'f' * 48}"
      with_secret_file(file_secret, mode: 0o400) do |path|
        assert_server_receives_secret(
          directory: directory,
          secret: file_secret,
          environment: { "SECRET_KEY_BASE_FILE" => path }
        )
      end
    end
  end

  test "claimed local Compose defines one service and volume without bootstrap material" do
    compose = compose_document(BASE_COMPOSE)
    services = compose.fetch("services")
    service = services.fetch("screenote")

    assert_equal [ "screenote" ], services.keys
    assert_equal [ "screenote_storage" ], compose.fetch("volumes").keys
    assert_equal [ "screenote_storage:/rails/storage" ], service.fetch("volumes")
    assert_equal "1000:1000", service.fetch("user")
    assert_equal "unless-stopped", service.fetch("restart")
    assert_equal "30s", service.fetch("stop_grace_period")
    assert_equal [ "${SCREENOTE_PORT:-3005}:80" ], service.fetch("ports")
    assert_equal "true", service.dig("environment", "DISABLE_SSL")
    assert_equal "self_hosted", service.dig("environment", "SCREENOTE_EDITION")
    assert_equal "1", service.dig("environment", "SCREENOTE_FORWARDED_CLIENT_HOPS")
    assert_equal "${SCREENOTE_TRUSTED_PROXIES:-127.0.0.1/32,::1/128}",
      service.dig("environment", "SCREENOTE_TRUSTED_PROXIES")
    assert_equal "/run/secrets/screenote_secret_key_base", service.dig("environment", "SECRET_KEY_BASE_FILE")
    assert_nil service.dig("environment", "SCREENOTE_BOOTSTRAP_TOKEN_FILE")
    assert_equal [ "screenote_secret_key_base" ], compose.fetch("secrets").keys
    assert_includes service.dig("healthcheck", "test").last, "127.0.0.1:80/ready"

    service.fetch("secrets").each do |secret|
      assert_equal "1000", secret.fetch("uid")
      assert_equal "1000", secret.fetch("gid")
      assert_equal 0o400, secret.fetch("mode")
    end

    direct_secret_names = service.fetch("environment").keys & FILE_BACKED_SECRET_NAMES
    assert_empty direct_secret_names
  end

  test "bootstrap overlay is the only Compose configuration that mounts bootstrap material" do
    overlay = compose_document(BOOTSTRAP_COMPOSE)
    service = overlay.dig("services", "screenote")

    assert_equal [ "screenote" ], overlay.fetch("services").keys
    assert_equal "/run/secrets/screenote_bootstrap_token",
      service.dig("environment", "SCREENOTE_BOOTSTRAP_TOKEN_FILE")
    assert_equal [ "screenote_bootstrap_token" ], overlay.fetch("secrets").keys
    assert_restricted_secret service.fetch("secrets").sole,
      source: "screenote_bootstrap_token",
      target: "screenote_bootstrap_token"
  end

  test "S3 overlay supplies complete generic settings and file-backed credentials" do
    overlay = compose_document(S3_COMPOSE)
    service = overlay.dig("services", "screenote")
    environment = service.fetch("environment")

    assert_equal [ "screenote" ], overlay.fetch("services").keys
    assert_equal "s3", environment.fetch("SCREENOTE_STORAGE")
    %w[
      SCREENOTE_S3_ENDPOINT
      SCREENOTE_S3_REGION
      SCREENOTE_S3_BUCKET
      SCREENOTE_S3_PREFIX
      SCREENOTE_S3_PATH_STYLE
      SCREENOTE_S3_REQUEST_TIMEOUT
      SCREENOTE_S3_RETRY_LIMIT
      AWS_REQUEST_CHECKSUM_CALCULATION
      AWS_RESPONSE_CHECKSUM_VALIDATION
    ].each { |name| assert environment.key?(name), name }
    assert_equal "/run/secrets/screenote_s3_access_key_id",
      environment.fetch("SCREENOTE_S3_ACCESS_KEY_ID_FILE")
    assert_equal "/run/secrets/screenote_s3_secret_access_key",
      environment.fetch("SCREENOTE_S3_SECRET_ACCESS_KEY_FILE")
    assert_equal %w[screenote_s3_access_key_id screenote_s3_secret_access_key], overlay.fetch("secrets").keys
    service.fetch("secrets").each { |secret| assert_restricted_secret(secret) }

    direct_secret_names = environment.keys & FILE_BACKED_SECRET_NAMES
    assert_empty direct_secret_names
  end

  test "optional provider overlays mount each credential from a restricted file" do
    expectations = {
      smtp: [ "SMTP_PASSWORD_FILE", "/run/secrets/screenote_smtp_password", "screenote_smtp_password" ],
      google_oauth: [ "GOOGLE_CLIENT_SECRET_FILE", "/run/secrets/screenote_google_client_secret", "screenote_google_client_secret" ],
      github_oauth: [ "GITHUB_CLIENT_SECRET_FILE", "/run/secrets/screenote_github_client_secret", "screenote_github_client_secret" ],
      honeybadger: [ "HONEYBADGER_API_KEY_FILE", "/run/secrets/screenote_honeybadger_api_key", "screenote_honeybadger_api_key" ]
    }

    OPTIONAL_PROVIDER_COMPOSE.each do |provider, path|
      overlay = compose_document(path)
      service = overlay.dig("services", "screenote")
      file_variable, target_path, secret_name = expectations.fetch(provider)

      assert_equal [ "screenote" ], overlay.fetch("services").keys, provider
      assert_equal target_path, service.dig("environment", file_variable), provider
      assert_equal [ secret_name ], overlay.fetch("secrets").keys, provider
      assert_restricted_secret service.fetch("secrets").sole,
        source: secret_name,
        target: File.basename(target_path)
      assert_empty service.fetch("environment").keys & FILE_BACKED_SECRET_NAMES, provider
    end
  end

  test "all supported Compose modes render one service and volume without embedding secret values" do
    image = "ghcr.io/ivankuznetsov/screenote@sha256:#{'a' * 64}"
    environment = {
      "SCREENOTE_IMAGE" => image,
      "SCREENOTE_BASE_URL" => "http://screenote.internal:3005",
      "SCREENOTE_SECRET_KEY_BASE_PATH" => "/operator/secrets/secret_key_base",
      "SCREENOTE_BOOTSTRAP_TOKEN_PATH" => "/operator/secrets/bootstrap_token",
      "SCREENOTE_S3_ENDPOINT" => "https://objects.example.test",
      "SCREENOTE_S3_REGION" => "local",
      "SCREENOTE_S3_BUCKET" => "screenote-private",
      "SCREENOTE_S3_PREFIX" => "team-one",
      "SCREENOTE_S3_ACCESS_KEY_ID_PATH" => "/operator/secrets/s3_access_key_id",
      "SCREENOTE_S3_SECRET_ACCESS_KEY_PATH" => "/operator/secrets/s3_secret_access_key",
      "SMTP_ADDRESS" => "smtp.example.test",
      "SMTP_USERNAME" => "screenote",
      "MAILER_FROM" => "screenote@example.test",
      "SCREENOTE_SMTP_PASSWORD_PATH" => "/operator/secrets/smtp_password",
      "GOOGLE_CLIENT_ID" => "google-client-id",
      "SCREENOTE_GOOGLE_CLIENT_SECRET_PATH" => "/operator/secrets/google_client_secret",
      "GITHUB_CLIENT_ID" => "github-client-id",
      "SCREENOTE_GITHUB_CLIENT_SECRET_PATH" => "/operator/secrets/github_client_secret",
      "SCREENOTE_HONEYBADGER_API_KEY_PATH" => "/operator/secrets/honeybadger_api_key"
    }
    modes = {
      claimed_local: [ BASE_COMPOSE ],
      fresh_local: [ BASE_COMPOSE, BOOTSTRAP_COMPOSE ],
      claimed_s3: [ BASE_COMPOSE, S3_COMPOSE ],
      fresh_s3: [ BASE_COMPOSE, BOOTSTRAP_COMPOSE, S3_COMPOSE ],
      claimed_all_providers: [ BASE_COMPOSE, S3_COMPOSE, *OPTIONAL_PROVIDER_COMPOSE.values ]
    }

    modes.each do |mode, files|
      stdout, stderr, status = compose_config(*files, environment: environment)

      assert status.success?, "#{mode}: #{stderr}"
      rendered = YAML.safe_load(stdout, aliases: true)
      assert_equal [ "screenote" ], rendered.fetch("services").keys, mode
      assert_equal [ "screenote_storage" ], rendered.fetch("volumes").keys, mode
      assert_includes stdout, image, mode
      FILE_BACKED_SECRET_NAMES.each do |name|
        assert_not_includes stdout, "#{name}:", "#{mode} embeds #{name}"
      end
    end

    claimed_stdout, = compose_config(BASE_COMPOSE, environment: environment)
    assert_not_includes claimed_stdout, "screenote_bootstrap_token"

    s3_stdout, = compose_config(BASE_COMPOSE, S3_COMPOSE, environment: environment)
    assert_includes s3_stdout, "SCREENOTE_S3_ACCESS_KEY_ID_FILE"
    assert_includes s3_stdout, "SCREENOTE_S3_SECRET_ACCESS_KEY_FILE"

    example = Rails.root.join(".env.self-hosted.example").read
    FILE_BACKED_SECRET_NAMES.each do |name|
      assert_no_match(/^#{Regexp.escape(name)}=/, example)
    end
    assert_match(/^SCREENOTE_SECRET_KEY_BASE_PATH=/, example)
    assert_match(/^SCREENOTE_BOOTSTRAP_TOKEN_PATH=/, example)
    assert_match(/^SCREENOTE_S3_ACCESS_KEY_ID_PATH=/, example)
    assert_match(/^SCREENOTE_S3_SECRET_ACCESS_KEY_PATH=/, example)
    assert_match(/^SCREENOTE_SMTP_PASSWORD_PATH=/, example)
    assert_match(/^SCREENOTE_GOOGLE_CLIENT_SECRET_PATH=/, example)
    assert_match(/^SCREENOTE_GITHUB_CLIENT_SECRET_PATH=/, example)
    assert_match(/^SCREENOTE_HONEYBADGER_API_KEY_PATH=/, example)
  end

  test "the final image bounds requests above the supported image upload size" do
    dockerfile = Rails.root.join("Dockerfile").read

    assert_match(/MAX_REQUEST_BODY="31457280"/, dockerfile)
  end

  test "the final image defaults to the ONCE self hosted proxy contract" do
    dockerfile = Rails.root.join("Dockerfile").read

    assert_match(/SCREENOTE_EDITION="self_hosted"/, dockerfile)
    assert_match(/DISABLE_SSL="false"/, dockerfile)
    assert_match(/THRUSTER_FORWARD_HEADERS="true"/, dockerfile)
    assert_match(/SCREENOTE_FORWARDED_CLIENT_HOPS="2"/, dockerfile)
    assert_match(/SCREENOTE_FORWARDED_PROXY_HOST="once-proxy"/, dockerfile)
    assert_match(
      /SCREENOTE_TRUSTED_PROXIES="127\.0\.0\.1\/32,::1\/128"/,
      dockerfile
    )
    assert_match(
      /ARG SCREENOTE_IMAGE_REVISION="development"\n.*ENV KAMAL_VERSION="\$SCREENOTE_IMAGE_REVISION"/m,
      dockerfile
    )
  end

  test "the final image provides both ONCE storage mount points to uid and gid 1000" do
    dockerfile = Rails.root.join("Dockerfile").read

    assert_match(/addgroup -S -g 1000 rails/, dockerfile)
    assert_match(/adduser -S -D -u 1000 -G rails/, dockerfile)
    assert_match(/mkdir -p \/storage \/rails\/storage/, dockerfile)
    assert_match(/chown rails:rails \/storage \/rails\/storage/, dockerfile)
  end

  private

  def assert_server_receives_secret(directory:, secret:, environment:)
    trace = File.join(directory, "server-environment")
    bootstrap_secret = "bootstrap-secret-#{'b' * 32}"
    FileUtils.rm_f(trace)
    stdout, stderr, status = run_entrypoint(
      {
        "SCREENOTE_EDITION" => "saas",
        "SCREENOTE_BOOTSTRAP_TOKEN" => bootstrap_secret,
        "SCREENOTE_TEST_EXPECTED_SECRET" => secret,
        "SCREENOTE_TEST_TRACE" => trace
      }.merge(environment),
      "./bin/thrust", "./bin/rails", "server",
      chdir: directory
    )

    assert status.success?, stderr
    assert_equal "secret=matched bootstrap=absent secret_file=absent\n", File.binread(trace)
    assert_not_includes stdout, secret
    assert_not_includes stderr, secret
    assert_not_includes stdout, bootstrap_secret
    assert_not_includes stderr, bootstrap_secret
  end

  def run_entrypoint(environment, *command, chdir: Rails.root.to_s)
    clean_environment = FILE_BACKED_SECRET_NAMES.flat_map do |name|
      [ [ name, nil ], [ "#{name}_FILE", nil ] ]
    end.to_h
    %w[DATABASE_URL CACHE_DATABASE_URL QUEUE_DATABASE_URL CABLE_DATABASE_URL].each do |name|
      clean_environment[name] = nil
    end
    clean_environment.merge!(environment)

    Open3.capture3(clean_environment, ENTRYPOINT, *command, chdir: chdir)
  end

  def compose_document(path)
    YAML.safe_load(path.read, aliases: true)
  end

  def compose_config(*files, environment:)
    command = [ "docker", "compose" ]
    files.each { |file| command.concat([ "-f", file.to_s ]) }
    command << "config"
    Open3.capture3(environment, *command, chdir: Rails.root.to_s)
  end

  def assert_restricted_secret(secret, source: nil, target: nil)
    assert_equal source, secret.fetch("source") if source
    assert_equal target, secret.fetch("target") if target
    assert_equal "1000", secret.fetch("uid")
    assert_equal "1000", secret.fetch("gid")
    assert_equal 0o400, secret.fetch("mode")
  end

  def with_secret_file(value, mode:)
    Dir.mktmpdir("screenote-secret") do |directory|
      path = File.join(directory, "secret")
      File.binwrite(path, "#{value}\n")
      File.chmod(mode, path)
      yield path
    end
  end

  def write_executable(path, contents)
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, contents)
    File.chmod(0o700, path)
  end

  def install_actual_preflight(directory, storage_root:)
    command = Shellwords.escape(Rails.root.join("bin/screenote-deployment-preflight").to_s)
    root = Shellwords.escape(storage_root)
    write_executable(
      File.join(directory, "bin/screenote-deployment-preflight"),
      "#!/usr/bin/env bash\nSCREENOTE_STORAGE_ROOT=#{root} exec #{command}\n"
    )
  end

  def create_installation_primary(storage_root, deployment_mode:)
    path = File.join(storage_root, "primary.sqlite3")
    database = SQLite3::Database.new(path)
    database.execute(<<~SQL)
      CREATE TABLE installations (
        singleton_key varchar NOT NULL,
        deployment_mode varchar NOT NULL
      )
    SQL
    database.execute(
      "INSERT INTO installations (singleton_key, deployment_mode) VALUES (?, ?)",
      [ "screenote", deployment_mode ]
    )
    path
  ensure
    database&.close
  end

  def create_self_hosted_identity_primary(storage_root, environment:)
    deployment = Screenote::Deployment.new(environment, production: true)
    path = File.join(storage_root, "primary.sqlite3")
    database = SQLite3::Database.new(path)
    database.execute(<<~SQL)
      CREATE TABLE installations (
        singleton_key varchar NOT NULL,
        deployment_mode varchar NOT NULL,
        storage_service varchar NOT NULL,
        storage_namespace_fingerprint varchar NOT NULL,
        state varchar NOT NULL,
        bootstrap_token_digest varchar
      )
    SQL
    database.execute(
      <<~SQL,
        INSERT INTO installations (
          singleton_key, deployment_mode, storage_service,
          storage_namespace_fingerprint, state, bootstrap_token_digest
        ) VALUES (?, ?, ?, ?, ?, ?)
      SQL
      [
        "screenote",
        "self_hosted",
        deployment.active_storage_service.to_s,
        deployment.storage_namespace_fingerprint,
        "unclaimed",
        deployment.bootstrap_token_digest
      ]
    )
    database.execute("CREATE TABLE schema_migrations (version varchar NOT NULL PRIMARY KEY)")
    database.execute("INSERT INTO schema_migrations (version) VALUES ('20260805110000')")
    path
  ensure
    database&.close
  end
end
