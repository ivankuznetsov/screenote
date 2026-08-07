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

    OauthDeviceGrant.cleanup_expired!

    assert_not OauthDeviceGrant.exists?(stale_grant.id)
    assert OauthDeviceGrant.exists?(recently_expired_grant.id)
    assert OauthDeviceGrant.exists?(active_grant.id)
  end

  test "approval requires a current resource owner authority binding" do
    grant = build_grant(
      user_code: "OWNER-CHECK",
      resource_owner: nil,
      principal_kind: "user",
      approved_at: Time.current
    )

    assert_not grant.valid?
    assert_includes grant.errors[:principal_kind],
      "must identify authority the resource owner currently holds"
  end

  test "authority cannot be selected before approval" do
    grant = build_grant(user_code: "EARLY-CHECK", principal_kind: "user")

    assert_not grant.valid?
    assert_includes grant.errors[:principal_kind], "cannot be selected before approval"
  end

  test "approved authority binding is immutable" do
    grant = build_grant(
      user_code: "BOUND-CHECK",
      resource_owner: users(:alice),
      principal_kind: "user",
      approved_at: Time.current
    )
    grant.save!

    assert grant.update(polling_interval: grant.polling_interval + 1)

    assert_not grant.update(principal_kind: "project", project: projects(:alice_project))
    assert_includes grant.errors[:principal_kind], "cannot change after approval"
    assert_equal "user", grant.reload.principal_kind
    assert_nil grant.project_id
  end

  private

  def create_grant(user_code:, expires_at:)
    build_grant(user_code: user_code, expires_at: expires_at).tap(&:save!)
  end

  def build_grant(user_code:, expires_at: 10.minutes.from_now, **attributes)
    OauthDeviceGrant.new(
      application: @application,
      device_code: SecureRandom.hex(32),
      user_code: user_code,
      scopes: "mcp_read",
      expires_at: expires_at,
      **attributes
    )
  end
end
