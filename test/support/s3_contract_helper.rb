# frozen_string_literal: true

require "aws-sdk-s3"

# Shared wiring for the S3 compatibility gate. Everything here reads the same
# operator-supplied configuration that `script/release_test_matrix s3` passes to
# a real object store, so a suite either runs against that store or says so.
module S3ContractHelper
  private

  # Skips when nobody configured an object store and fails closed when the s3
  # gate did, so this coverage can never be quietly reported as passing.
  def require_s3_contract!
    required = ENV["SCREENOTE_REQUIRE_S3"] == "1"
    missing = %w[
      SCREENOTE_S3_ENDPOINT SCREENOTE_S3_REGION SCREENOTE_S3_BUCKET
      SCREENOTE_S3_PREFIX SCREENOTE_S3_ACCESS_KEY_ID SCREENOTE_S3_SECRET_ACCESS_KEY
    ].reject { |name| ENV[name].present? }
    return if missing.empty?

    flunk "S3 matrix missing #{missing.join(', ')}" if required
    skip "run through script/release_test_matrix s3 against MinIO"
  end

  def storage_service
    ActiveStorage::Service::PrefixedS3Service.new(
      bucket: bucket,
      prefix: prefix,
      **client_options,
      http_open_timeout: 2,
      http_read_timeout: 2,
      retry_limit: 1
    )
  end

  # Points the whole application at the object store for the duration of the
  # block. Registering a named service is what makes new blobs record it, so
  # every later read resolves back through the same provider.
  def with_s3_active_storage(name: :s3_contract)
    original_services = ActiveStorage::Blob.services
    original_service = ActiveStorage::Blob.service
    configurations = Rails.application.config.active_storage.service_configurations.merge(
      name.to_s => {
        "service" => "PrefixedS3",
        "bucket" => bucket,
        "prefix" => prefix,
        "region" => region,
        "access_key_id" => access_key,
        "secret_access_key" => secret_key,
        "endpoint" => ENV.fetch("SCREENOTE_S3_ENDPOINT"),
        "force_path_style" => true,
        "http_open_timeout" => 5,
        "http_read_timeout" => 5,
        "retry_limit" => 1
      }
    )
    registry = ActiveStorage::Service::Registry.new(configurations)
    ActiveStorage::Blob.services = registry
    ActiveStorage::Blob.service = registry.fetch(name)
    yield ActiveStorage::Blob.service
  ensure
    ActiveStorage::Blob.services = original_services
    ActiveStorage::Blob.service = original_service
  end

  def client_options
    {
      region: region,
      access_key_id: access_key,
      secret_access_key: secret_key,
      endpoint: ENV.fetch("SCREENOTE_S3_ENDPOINT"),
      force_path_style: true
    }
  end

  def bucket
    ENV.fetch("SCREENOTE_S3_BUCKET")
  end

  def prefix
    ENV.fetch("SCREENOTE_S3_PREFIX")
  end

  def region
    ENV.fetch("SCREENOTE_S3_REGION")
  end

  def access_key
    ENV.fetch("SCREENOTE_S3_ACCESS_KEY_ID")
  end

  def secret_key
    ENV.fetch("SCREENOTE_S3_SECRET_ACCESS_KEY")
  end
end
