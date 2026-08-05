# frozen_string_literal: true

module Installations
  class Prepare
    class ConfigurationMismatch < StandardError; end

    MAX_CREATE_ATTEMPTS = 2

    def self.call(deployment: Screenote::Deployment.current)
      new(deployment).call
    end

    def initialize(deployment)
      @deployment = deployment
    end

    def call
      attempts = 0

      begin
        attempts += 1
        Installation.transaction(requires_new: true) do
          installation = Installation.lock.find_by(singleton_key: Installation::SINGLETON_KEY)
          installation ? verify!(installation) : Installation.create!(creation_attributes)
        end
      rescue ActiveRecord::RecordNotUnique
        retry if attempts < MAX_CREATE_ATTEMPTS

        raise
      end
    end

    private

    attr_reader :deployment

    def creation_attributes
      if deployment.self_hosted? && deployment.bootstrap_token_digest.nil?
        raise ConfigurationMismatch,
          "A fresh self-hosted installation requires bootstrap material; provide SCREENOTE_BOOTSTRAP_TOKEN"
      end

      {
        singleton_key: Installation::SINGLETON_KEY,
        deployment_mode: deployment.edition.to_s,
        state: deployment.saas? ? "saas" : "unclaimed",
        storage_service: deployment.active_storage_service.to_s,
        storage_namespace_fingerprint: deployment.storage_namespace_fingerprint,
        bootstrap_token_digest: deployment.bootstrap_token_digest
      }
    end

    def verify!(installation)
      mismatches = []
      if installation.deployment_mode != deployment.edition.to_s
        mismatches << "deployment mode is #{installation.deployment_mode.inspect}, configured #{deployment.edition.inspect}"
      end
      if installation.storage_service != deployment.active_storage_service.to_s
        mismatches << "storage service is #{installation.storage_service.inspect}, configured #{deployment.active_storage_service.inspect}"
      end
      if installation.storage_namespace_fingerprint != deployment.storage_namespace_fingerprint
        mismatches << "storage namespace differs from the prepared installation"
      end
      if installation.unclaimed? && installation.bootstrap_token_digest != deployment.bootstrap_token_digest
        mismatches << "bootstrap material differs from the unclaimed installation"
      end

      unless mismatches.empty?
        raise ConfigurationMismatch,
          "Refusing to start with a different persisted installation identity: #{mismatches.join('; ')}"
      end

      installation
    end
  end
end
