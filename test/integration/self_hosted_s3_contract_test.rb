# frozen_string_literal: true

# screenote-edition: self_hosted

require "test_helper"
require_relative "../support/s3_contract_helper"
require "base64"
require "stringio"

class SelfHostedS3ContractTest < ActiveSupport::TestCase
  include S3ContractHelper

  setup do
    require_s3_contract!
    @client = Aws::S3::Client.new(client_options)
    @client.create_bucket(bucket: bucket)
  rescue Aws::S3::Errors::BucketAlreadyOwnedByYou
    nil
  end

  teardown do
    next unless defined?(@client) && @client

    @client.list_objects_v2(bucket: bucket, prefix: prefix).contents.each do |object|
      @client.delete_object(bucket: bucket, key: object.key)
    end
  end

  test "MinIO supports upload checksum range read analysis variant existence and delete" do
    require_vips!
    service = storage_service
    bytes = file_fixture("test_image.png").binread
    checksum = Base64.strict_encode64(Digest::MD5.digest(bytes))

    service.upload("original", StringIO.new(bytes), checksum: checksum)

    assert service.exist?("original")
    assert_equal bytes, service.download("original")
    assert_equal bytes.byteslice(0, 16), service.download_chunk("original", 0..15)
    original = Vips::Image.new_from_buffer(service.download("original"), "")
    assert_operator original.width, :>, 0
    assert_operator original.height, :>, 0

    variant = original.thumbnail_image(32).write_to_buffer(".png")
    service.upload(
      "variants/original/32",
      StringIO.new(variant),
      checksum: Base64.strict_encode64(Digest::MD5.digest(variant))
    )
    decoded_variant = Vips::Image.new_from_buffer(service.download("variants/original/32"), "")
    assert_operator decoded_variant.width, :<=, 32
    assert_operator decoded_variant.height, :<=, 32

    signed_url = service.url(
      "original",
      expires_in: 60,
      disposition: :inline,
      filename: ActiveStorage::Filename.new("original.png"),
      content_type: "image/png"
    )
    assert_includes signed_url, bucket
    assert_includes signed_url, "#{prefix}/original"

    service.delete("original")
    service.delete_prefixed("variants/")
    assert_not service.exist?("original")
    assert_not service.exist?("variants/original/32")
  end

  test "an unavailable provider fails within the configured retry budget" do
    unavailable = ActiveStorage::Service::PrefixedS3Service.new(
      bucket: bucket,
      prefix: prefix,
      region: region,
      access_key_id: access_key,
      secret_access_key: secret_key,
      endpoint: "http://127.0.0.1:1",
      force_path_style: true,
      http_open_timeout: 1,
      http_read_timeout: 1,
      retry_limit: 0
    )
    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)

    assert_raises(Aws::Errors::ServiceError, Seahorse::Client::NetworkingError) do
      unavailable.exist?("outage-probe")
    end
    assert_operator Process.clock_gettime(Process::CLOCK_MONOTONIC) - started, :<, 5
  end
end
