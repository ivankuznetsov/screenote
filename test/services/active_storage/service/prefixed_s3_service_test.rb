# frozen_string_literal: true

require "test_helper"

class ActiveStorage::Service::PrefixedS3ServiceTest < ActiveSupport::TestCase
  test "every object key is scoped below the configured prefix" do
    service = ActiveStorage::Service::PrefixedS3Service.new(
      bucket: "screenote-private",
      prefix: "team-one/screenshots",
      region: "us-east-1",
      access_key_id: "test-access",
      secret_access_key: "test-secret",
      stub_responses: true
    )

    object = service.send(:object_for, "active-storage-key")

    assert_equal "team-one/screenshots/active-storage-key", object.key
  end
end
