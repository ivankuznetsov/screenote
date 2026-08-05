# frozen_string_literal: true

require "sqlite3"
require_relative "deployment"

module Screenote
  class DeploymentPreflight
    class Mismatch < StandardError; end

    EDITIONS = %w[saas self_hosted].freeze
    SAAS_DATABASE_KEYS = %w[
      DATABASE_URL
      CACHE_DATABASE_URL
      QUEUE_DATABASE_URL
      CABLE_DATABASE_URL
    ].freeze
    PRIMARY_DATABASE = "primary.sqlite3"
    INSTALLATION_KEY = "screenote"

    def self.call(environment: ENV, storage_root: "/rails/storage")
      new(environment:, storage_root:).call
    end

    def initialize(environment:, storage_root:)
      @environment = environment
      @storage_root = storage_root
    end

    def call
      validate_edition!

      if edition == "saas"
        reject_local_primary_for_saas!
      else
        reject_saas_database_configuration!
        verify_local_identity!(configured_deployment)
      end

      :ok
    end

    private

    attr_reader :environment, :storage_root

    def edition
      @edition ||= environment["SCREENOTE_EDITION"].to_s.strip
    end

    def primary_database_path
      File.join(storage_root, PRIMARY_DATABASE)
    end

    def validate_edition!
      return if EDITIONS.include?(edition)

      raise Mismatch, "SCREENOTE_EDITION must be saas or self_hosted"
    end

    def reject_local_primary_for_saas!
      return unless File.exist?(primary_database_path) || File.symlink?(primary_database_path)

      raise Mismatch,
        "durable self-hosted primary exists but the configured edition is saas"
    end

    def reject_saas_database_configuration!
      configured_keys = SAAS_DATABASE_KEYS.select do |key|
        !environment[key].to_s.strip.empty?
      end
      return if configured_keys.empty?

      raise Mismatch,
        "self-hosted startup cannot retain SaaS database settings: #{configured_keys.join(', ')}"
    end

    def configured_deployment
      Screenote::Deployment.new(environment, production: true)
    rescue Screenote::Deployment::ConfigurationError => error
      raise Mismatch, error.message
    end

    def verify_local_identity!(deployment)
      path = primary_database_path
      return unless File.exist?(path) || File.symlink?(path)

      unless File.file?(path) && !File.symlink?(path)
        raise Mismatch, "cannot verify existing self-hosted primary"
      end

      database = SQLite3::Database.new(path, readonly: true)
      database.busy_timeout = 1_000
      return unless installations_table?(database)

      rows = database.execute(
        <<~SQL
          SELECT singleton_key, deployment_mode, storage_service,
            storage_namespace_fingerprint, state, bootstrap_token_digest
          FROM installations
          LIMIT 2
        SQL
      )
      return if rows.empty?

      unless rows.one? && rows.first.first(2) == [ INSTALLATION_KEY, "self_hosted" ]
        raise Mismatch,
          "existing primary installation identity does not match self_hosted"
      end

      _singleton_key, _deployment_mode, storage_service,
        storage_fingerprint, state, bootstrap_digest = rows.first
      mismatches = []
      if storage_service != deployment.active_storage_service.to_s
        mismatches << "storage service differs from the prepared installation"
      end
      if storage_fingerprint != deployment.storage_namespace_fingerprint
        mismatches << "storage namespace differs from the prepared installation"
      end
      if state == "unclaimed"
        if bootstrap_digest != deployment.bootstrap_token_digest
          mismatches << "bootstrap material differs from the unclaimed installation"
        end
      elsif state != "claimed" || bootstrap_digest
        mismatches << "ownership state is invalid"
      end

      return if mismatches.empty?

      raise Mismatch,
        "Refusing to start with a different persisted installation identity: #{mismatches.join('; ')}"
    rescue SQLite3::Exception, SystemCallError
      raise Mismatch, "cannot verify existing self-hosted primary"
    ensure
      database&.close
    end

    def installations_table?(database)
      database.get_first_value(<<~SQL) == "installations"
        SELECT name
        FROM sqlite_master
        WHERE type = 'table' AND name = 'installations'
      SQL
    end
  end
end
