# frozen_string_literal: true

require "base64"
require "digest"
require "json"
require "net/http"
require "securerandom"
require "socket"
require "stringio"
require "tempfile"
require "timeout"
require "uri"

module Screenote
  class SelfHostedDiagnostics
    Result = Data.define(:success?, :payload)
    STORAGE_PROBE_BYTES = "screenote-storage-diagnostic-v1".b.freeze
    OAUTH_PROBE_URLS = {
      google_oauth2: "https://accounts.google.com/.well-known/openid-configuration",
      github: "https://github.com/login/oauth/authorize"
    }.freeze

    def initialize(
      deployment: Screenote::Deployment.current,
      role_connections: default_role_connections,
      storage_service: ActiveStorage::Blob.service,
      storage_root: Screenote::Readiness::STORAGE_ROOT,
      smtp_probe: method(:probe_smtp),
      oauth_probe: method(:probe_oauth)
    )
      @deployment = deployment
      @role_connections = role_connections
      @storage_service = storage_service
      @storage_root = storage_root
      @smtp_probe = smtp_probe
      @oauth_probe = oauth_probe
    end

    def call
      raise Screenote::Deployment::ConfigurationError, "diagnostics require self-hosted mode" unless deployment.self_hosted?

      checks = {
        databases: database_checks,
        volume: volume_check,
        storage: storage_check,
        smtp: smtp_check,
        oauth: oauth_check,
        monitoring: monitoring_check
      }
      success = checks.fetch(:databases).values.all? { |status| status == "ok" } &&
        checks.values_at(:volume, :storage, :smtp, :oauth).all? { |check| check_successful?(check) }
      Result.new(
        success?: success,
        payload: {
          schema: "screenote-self-host-diagnostics/v1",
          status: success ? "ok" : "failed",
          checks: checks
        }
      )
    end

    private

    attr_reader :deployment, :role_connections, :storage_service, :storage_root,
      :smtp_probe, :oauth_probe

    def default_role_connections
      {
        primary: ActiveRecord::Base,
        cache: SolidCache::Record,
        queue: SolidQueue::Record,
        cable: SolidCable::Record
      }
    end

    def database_checks
      Screenote::Readiness::ROLE_TABLES.to_h do |role, table|
        status = begin
          role_connections.fetch(role).connection_pool.with_connection do |connection|
            raise "schema missing" unless connection.data_source_exists?(table)
            raise "integrity failed" unless connection.select_value("PRAGMA integrity_check") == "ok"
            raise "foreign keys failed" unless connection.select_rows("PRAGMA foreign_key_check").empty?
          end
          "ok"
        rescue StandardError
          "unavailable"
        end
        [ role, status ]
      end
    end

    def volume_check
      Tempfile.create([ ".screenote-diagnostic-", ".tmp" ], storage_root) do |file|
        file.write(STORAGE_PROBE_BYTES)
        file.flush
        file.fsync
      end
      { status: "ok" }
    rescue StandardError
      { status: "unavailable" }
    end

    def storage_check
      key = "diagnostics/#{SecureRandom.hex(24)}"
      checksum = Base64.strict_encode64(Digest::MD5.digest(STORAGE_PROBE_BYTES))
      storage_service.upload(key, StringIO.new(STORAGE_PROBE_BYTES), checksum: checksum)
      raise "storage write did not become visible" unless storage_service.exist?(key)
      raise "storage round trip changed bytes" unless storage_service.download(key) == STORAGE_PROBE_BYTES

      { profile: storage_profile, status: "ok" }
    rescue StandardError
      { profile: storage_profile, status: "unavailable" }
    ensure
      begin
        storage_service.delete(key) if key
      rescue StandardError
        nil
      end
    end

    def storage_profile
      deployment.active_storage_service == :self_hosted_s3 ? "s3" : "local"
    end

    def smtp_check
      configuration = deployment.mail_configuration
      return { status: "disabled" } if configuration.fetch(:provider) == :disabled

      smtp_probe.call(configuration.fetch(:address), configuration.fetch(:port))
      { status: "ok" }
    rescue StandardError
      { status: "unavailable" }
    end

    def oauth_check
      providers = deployment.social_oauth_providers
      return { status: "disabled", providers: {} } if providers.empty?

      statuses = providers.to_h do |provider|
        status = begin
          oauth_probe.call(provider)
          "ok"
        rescue StandardError
          "unavailable"
        end
        [ provider, status ]
      end
      { status: statuses.values.all?("ok") ? "ok" : "unavailable", providers: statuses }
    end

    def monitoring_check
      status = deployment.monitoring_configuration.fetch(:provider) == :disabled ? "disabled" : "configured"
      { status: status }
    end

    def check_successful?(check)
      %w[ok disabled].include?(check.fetch(:status))
    end

    def probe_smtp(address, port)
      Socket.tcp(address, port, connect_timeout: 5) { |socket| socket.close }
    end

    def probe_oauth(provider)
      uri = URI.parse(OAUTH_PROBE_URLS.fetch(provider))
      Net::HTTP.start(
        uri.host,
        uri.port,
        use_ssl: uri.scheme == "https",
        open_timeout: 5,
        read_timeout: 5,
        write_timeout: 5
      ) do |http|
        response = http.request(Net::HTTP::Head.new(uri.request_uri))
        raise "provider unavailable" if response.code.to_i >= 500
      end
    end
  end
end
