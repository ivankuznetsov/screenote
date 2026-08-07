# frozen_string_literal: true

# screenote-edition: self_hosted

require "test_helper"
require "base64"
require "digest"

class Screenote::SelfHostedRestoreVerifierTest < ActiveSupport::TestCase
  test "validates all databases and original objects before reclaiming durable work" do
    events = []
    bytes = "restored-private-object"
    service = StreamingStorage.new(bytes, events)
    blob = FakeBlob.new(
      "self_hosted_local",
      "opaque-key",
      bytes.bytesize,
      Base64.strict_encode64(Digest::MD5.digest(bytes))
    )
    deployment = FakeDeployment.new(:self_hosted_local, "f" * 64)
    installation = FakeInstallation.new("self_hosted", "self_hosted_local", "f" * 64)
    verifier = Screenote::SelfHostedRestoreVerifier.new(
      deployment:,
      installation:,
      role_connections: role_connections(events),
      blobs: [ blob ],
      storage_services: { self_hosted_local: service },
      keyring_preflight: -> { events << :keyring },
      queue_reclaimer: -> { events << :queue },
      processing_reconciler: -> { events << :processing }
    )

    result = verifier.call

    assert_equal({ database_roles: 4, blobs: 1 }, result)
    assert_operator events.index(:download), :<, events.index(:keyring)
    assert_operator events.index(:keyring), :<, events.index(:queue)
    assert_operator events.index(:queue), :<, events.index(:processing)
  end

  test "rejects a missing or changed object without reclaiming queue state" do
    events = []
    bytes = "restored-private-object"
    blob = FakeBlob.new(
      "self_hosted_s3",
      "opaque-key",
      bytes.bytesize,
      Base64.strict_encode64(Digest::MD5.digest(bytes))
    )
    deployment = FakeDeployment.new(:self_hosted_s3, "f" * 64)
    installation = FakeInstallation.new("self_hosted", "self_hosted_s3", "f" * 64)
    verifier = Screenote::SelfHostedRestoreVerifier.new(
      deployment:,
      installation:,
      role_connections: role_connections(events),
      blobs: [ blob ],
      storage_services: { self_hosted_s3: StreamingStorage.new("changed", events) },
      keyring_preflight: -> { events << :keyring },
      queue_reclaimer: -> { events << :queue },
      processing_reconciler: -> { events << :processing }
    )

    error = assert_raises(Screenote::SelfHostedRestoreVerifier::VerificationError) { verifier.call }

    assert_equal "restored object inventory is invalid", error.message
    assert_not_includes events, :keyring
    assert_not_includes events, :queue
    assert_not_includes events, :processing
  end

  test "rejects storage configuration drift before contacting object storage" do
    events = []
    verifier = Screenote::SelfHostedRestoreVerifier.new(
      deployment: FakeDeployment.new(:self_hosted_s3, "a" * 64),
      installation: FakeInstallation.new("self_hosted", "self_hosted_s3", "b" * 64),
      role_connections: role_connections(events),
      blobs: [],
      storage_services: {},
      keyring_preflight: -> { events << :keyring },
      queue_reclaimer: -> { events << :queue },
      processing_reconciler: -> { events << :processing }
    )

    error = assert_raises(Screenote::SelfHostedRestoreVerifier::VerificationError) { verifier.call }

    assert_equal "restored storage identity does not match runtime configuration", error.message
    assert_empty events
  end

  private

  FakeDeployment = Struct.new(:active_storage_service, :storage_namespace_fingerprint) do
    def self_hosted?
      true
    end
  end
  FakeInstallation = Struct.new(:deployment_mode, :storage_service, :storage_namespace_fingerprint)
  FakeBlob = Struct.new(:service_name, :key, :byte_size, :checksum)

  FakeConnection = Struct.new(:events, :role) do
    def select_value(sql)
      raise "unexpected query" unless sql == "PRAGMA integrity_check"

      events << [ role, :integrity ]
      "ok"
    end

    def select_rows(sql)
      raise "unexpected query" unless sql == "PRAGMA foreign_key_check"

      events << [ role, :foreign_keys ]
      []
    end
  end
  FakePool = Struct.new(:connection) do
    def with_connection
      yield connection
    end
  end
  FakeRole = Struct.new(:connection_pool)

  class StreamingStorage
    def initialize(bytes, events)
      @bytes = bytes
      @events = events
    end

    def exist?(_key)
      true
    end

    def download(_key)
      @events << :download
      yield @bytes.byteslice(0, 5)
      yield @bytes.byteslice(5..)
    end
  end

  def role_connections(events)
    Screenote::Readiness::ROLE_TABLES.keys.to_h do |role|
      [ role, FakeRole.new(FakePool.new(FakeConnection.new(events, role))) ]
    end
  end
end
