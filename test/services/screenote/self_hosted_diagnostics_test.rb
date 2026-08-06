# frozen_string_literal: true

# screenote-edition: self_hosted

require "test_helper"
require "json"
require "tmpdir"

class Screenote::SelfHostedDiagnosticsTest < ActiveSupport::TestCase
  test "checks every local component and reports disabled providers without contacting them" do
    Dir.mktmpdir("screenote-diagnostics") do |root|
      storage = RoundTripStorage.new
      deployment = FakeDeployment.new(
        :self_hosted_local,
        { provider: :disabled },
        [],
        { provider: :disabled }
      )
      diagnostics = Screenote::SelfHostedDiagnostics.new(
        deployment:,
        role_connections: role_connections,
        storage_service: storage,
        storage_root: root,
        smtp_probe: ->(*) { flunk "disabled SMTP was contacted" },
        oauth_probe: ->(*) { flunk "disabled OAuth was contacted" }
      )

      result = diagnostics.call

      assert result.success?
      assert_equal "ok", result.payload.fetch(:status)
      assert_equal %i[cable cache primary queue], result.payload.dig(:checks, :databases).keys.sort
      assert_equal "ok", result.payload.dig(:checks, :storage, :status)
      assert_equal "disabled", result.payload.dig(:checks, :smtp, :status)
      assert_equal "disabled", result.payload.dig(:checks, :oauth, :status)
      assert storage.deleted
      assert_empty Dir.children(root)
    end
  end

  test "reports selected S3 SMTP and OAuth failures with redacted stable categories" do
    Dir.mktmpdir("screenote-diagnostics") do |root|
      sentinel = "s3-secret-endpoint-and-credential"
      deployment = FakeDeployment.new(
        :self_hosted_s3,
        { provider: :smtp, address: sentinel, port: 587 },
        %i[google_oauth2 github],
        { provider: :honeybadger }
      )
      diagnostics = Screenote::SelfHostedDiagnostics.new(
        deployment:,
        role_connections: role_connections,
        storage_service: FailingStorage.new(sentinel),
        storage_root: root,
        smtp_probe: ->(*) { raise IOError, sentinel },
        oauth_probe: ->(*) { raise Timeout::Error, sentinel }
      )

      result = diagnostics.call
      rendered = JSON.generate(result.payload)

      assert_not result.success?
      assert_equal "failed", result.payload.fetch(:status)
      assert_equal "unavailable", result.payload.dig(:checks, :storage, :status)
      assert_equal "unavailable", result.payload.dig(:checks, :smtp, :status)
      assert_equal "unavailable", result.payload.dig(:checks, :oauth, :providers, :google_oauth2)
      assert_equal "unavailable", result.payload.dig(:checks, :oauth, :providers, :github)
      assert_equal "configured", result.payload.dig(:checks, :monitoring, :status)
      assert_not_includes rendered, sentinel
      assert_not_includes rendered, root
    end
  end

  test "fails a database integrity check without exposing the adapter exception" do
    Dir.mktmpdir("screenote-diagnostics") do |root|
      sentinel = "private-database-path"
      connections = role_connections
      connections[:queue] = FakeRole.new(FakePool.new(FailingConnection.new(sentinel)))
      deployment = FakeDeployment.new(:self_hosted_local, { provider: :disabled }, [], { provider: :disabled })
      diagnostics = Screenote::SelfHostedDiagnostics.new(
        deployment:,
        role_connections: connections,
        storage_service: RoundTripStorage.new,
        storage_root: root
      )

      result = diagnostics.call
      rendered = JSON.generate(result.payload)

      assert_not result.success?
      assert_equal "unavailable", result.payload.dig(:checks, :databases, :queue)
      assert_not_includes rendered, sentinel
    end
  end

  private

  FakeDeployment = Struct.new(
    :active_storage_service,
    :mail_configuration,
    :social_oauth_providers,
    :monitoring_configuration
  ) do
    def self_hosted?
      true
    end
  end

  FakeConnection = Struct.new(:integrity, :foreign_keys) do
    def data_source_exists?(_table)
      true
    end

    def select_value(sql)
      raise "unexpected query" unless sql == "PRAGMA integrity_check"

      integrity
    end

    def select_rows(sql)
      raise "unexpected query" unless sql == "PRAGMA foreign_key_check"

      foreign_keys
    end
  end

  class FailingConnection
    def initialize(message)
      @message = message
    end

    def data_source_exists?(_table)
      raise SQLite3::SQLException, @message
    end
  end

  FakePool = Struct.new(:connection) do
    def with_connection
      yield connection
    end
  end
  FakeRole = Struct.new(:connection_pool)

  class RoundTripStorage
    attr_reader :deleted

    def upload(key, io, checksum:)
      @key = key
      @bytes = io.read
      @checksum = checksum
    end

    def exist?(key)
      key == @key
    end

    def download(key)
      raise "wrong key" unless key == @key

      @bytes
    end

    def delete(key)
      @deleted = key == @key
    end
  end

  class FailingStorage
    def initialize(message)
      @message = message
    end

    def upload(*)
      raise Aws::S3::Errors::ServiceError.new(nil, @message)
    end

    def delete(*)
      nil
    end
  end

  def role_connections
    Screenote::Readiness::ROLE_TABLES.to_h do |role, _table|
      [ role, FakeRole.new(FakePool.new(FakeConnection.new("ok", []))) ]
    end
  end
end
