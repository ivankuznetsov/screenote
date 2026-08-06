# frozen_string_literal: true

require "base64"
require "digest"

module Screenote
  class SelfHostedRestoreVerifier
    class VerificationError < StandardError; end

    def initialize(
      deployment: Screenote::Deployment.current,
      installation: Installation.current,
      role_connections: default_role_connections,
      blobs: ActiveStorage::Blob.find_each,
      storage_services: ActiveStorage::Blob.services,
      keyring_preflight: -> { AuthenticationLinks::Runtime.keyring },
      queue_reclaimer: method(:reclaim_stale_queue_work),
      processing_reconciler: -> { ReconcileScreenshotProcessingJob.perform_later }
    )
      @deployment = deployment
      @installation = installation
      @role_connections = role_connections
      @blobs = blobs
      @storage_services = storage_services
      @keyring_preflight = keyring_preflight
      @queue_reclaimer = queue_reclaimer
      @processing_reconciler = processing_reconciler
    end

    def call
      validate_storage_identity!
      validate_databases!
      blob_count = validate_objects!
      keyring_preflight.call
      queue_reclaimer.call
      processing_reconciler.call

      { database_roles: Screenote::Readiness::ROLE_TABLES.size, blobs: blob_count }
    rescue VerificationError
      raise
    rescue StandardError
      raise VerificationError, "restored runtime verification failed"
    end

    private

    attr_reader :deployment, :installation, :role_connections, :blobs,
      :storage_services, :keyring_preflight, :queue_reclaimer, :processing_reconciler

    def default_role_connections
      {
        primary: ActiveRecord::Base,
        cache: SolidCache::Record,
        queue: SolidQueue::Record,
        cable: SolidCable::Record
      }
    end

    def validate_storage_identity!
      valid = deployment.self_hosted? && installation&.deployment_mode == "self_hosted" &&
        installation.storage_service == deployment.active_storage_service.to_s &&
        installation.storage_namespace_fingerprint == deployment.storage_namespace_fingerprint
      return if valid

      raise VerificationError, "restored storage identity does not match runtime configuration"
    end

    def validate_databases!
      Screenote::Readiness::ROLE_TABLES.each_key do |role|
        role_connections.fetch(role).connection_pool.with_connection do |connection|
          unless connection.select_value("PRAGMA integrity_check") == "ok" &&
              connection.select_rows("PRAGMA foreign_key_check").empty?
            raise VerificationError, "restored database validation failed"
          end
        end
      end
    rescue VerificationError
      raise
    rescue StandardError
      raise VerificationError, "restored database validation failed"
    end

    def validate_objects!
      count = 0
      blobs.each do |blob|
        validate_object!(blob)
        count += 1
      end
      count
    rescue VerificationError
      raise
    rescue StandardError
      raise VerificationError, "restored object inventory is invalid"
    end

    def validate_object!(blob)
      expected_service = installation.storage_service
      raise VerificationError, "restored object inventory is invalid" unless blob.service_name == expected_service

      service = storage_services.fetch(expected_service.to_sym)
      raise VerificationError, "restored object inventory is invalid" unless service.exist?(blob.key)

      byte_size = 0
      digest = Digest::MD5.new
      service.download(blob.key) do |chunk|
        byte_size += chunk.bytesize
        raise VerificationError, "restored object inventory is invalid" if byte_size > blob.byte_size

        digest.update(chunk)
      end
      checksum = Base64.strict_encode64(digest.digest)
      unless byte_size == blob.byte_size && secure_equal?(checksum, blob.checksum.to_s)
        raise VerificationError, "restored object inventory is invalid"
      end
    end

    def secure_equal?(left, right)
      return false unless left.bytesize == right.bytesize

      ActiveSupport::SecurityUtils.secure_compare(left, right)
    end

    def reclaim_stale_queue_work
      SolidQueue::Record.transaction do
        SolidQueue::ClaimedExecution.all.release_all
        SolidQueue::Process.delete_all
        raise VerificationError, "stale queue work could not be reclaimed" if SolidQueue::ClaimedExecution.exists?
      end
    end
  end
end
