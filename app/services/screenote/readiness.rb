# frozen_string_literal: true

require "tempfile"

module Screenote
  class Readiness
    ROLE_TABLES = {
      primary: "installations",
      cache: "solid_cache_entries",
      queue: "solid_queue_jobs",
      cable: "solid_cable_messages"
    }.freeze
    STORAGE_ROOT = "/rails/storage"

    def self.ready?
      new.ready?
    end

    def initialize(
      role_connections: default_role_connections,
      storage_root: STORAGE_ROOT,
      storage_services: ActiveStorage::Blob.services,
      deployment: Screenote::Deployment.current
    )
      @role_connections = role_connections
      @storage_root = storage_root
      @storage_services = storage_services
      @deployment = deployment
    end

    def ready?
      role_schemas_ready? && storage_volume_writable? && configured_storage_ready?
    rescue StandardError
      false
    end

    private

    attr_reader :role_connections, :storage_root, :storage_services, :deployment

    def default_role_connections
      {
        primary: ActiveRecord::Base,
        cache: SolidCache::Record,
        queue: SolidQueue::Record,
        cable: SolidCable::Record
      }
    end

    def role_schemas_ready?
      ROLE_TABLES.all? do |role, table|
        role_connections.fetch(role).connection_pool.with_connection do |connection|
          connection.data_source_exists?(table)
        end
      end
    end

    def storage_volume_writable?
      Tempfile.create([ ".screenote-readiness-", ".tmp" ], storage_root) do |file|
        file.write("ready")
        file.flush
      end
      true
    end

    def configured_storage_ready?
      storage_services.fetch(deployment.active_storage_service)
      true
    end
  end
end
