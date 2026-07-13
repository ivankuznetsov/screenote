# frozen_string_literal: true

require "test_helper"

class OauthDeviceGrantTest < ActiveSupport::TestCase
  setup do
    @application = create_oauth_application(name: "Device grant cleanup")
  end

  test "cleanup_expired deletes stale grants and retains recent terminal errors" do
    stale_grant = create_grant(
      user_code: "OLD12-CODE3",
      expires_at: OauthDeviceGrant::EXPIRED_RETENTION_PERIOD.ago - 1.minute
    )
    recently_expired_grant = create_grant(user_code: "DONE4-CODE5", expires_at: 1.minute.ago)
    active_grant = create_grant(user_code: "LIVE4-CODE5", expires_at: 1.minute.from_now)

    assert_difference "OauthDeviceGrant.count", -1 do
      OauthDeviceGrant.cleanup_expired!
    end

    assert_not OauthDeviceGrant.exists?(stale_grant.id)
    assert OauthDeviceGrant.exists?(recently_expired_grant.id)
    assert OauthDeviceGrant.exists?(active_grant.id)
  end

  private

  def create_grant(user_code:, expires_at:)
    OauthDeviceGrant.create!(
      application: @application,
      device_code: SecureRandom.hex(32),
      user_code: user_code,
      scopes: "mcp_read",
      expires_at: expires_at
    )
  end
end
