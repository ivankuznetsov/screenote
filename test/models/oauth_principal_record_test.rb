# frozen_string_literal: true

require "test_helper"

class OauthPrincipalRecordTest < ActiveSupport::TestCase
  setup do
    @user = users(:alice)
    @project = projects(:alice_project)
    @application = create_oauth_application(name: "Principal immutability")
  end

  test "new token and application secrets are one-way hashed at rest" do
    token = create_oauth_token(application: @application, user: @user)
    raw_token = token.token
    confidential_application = create_oauth_application(
      name: "Hashed confidential client",
      confidential: true
    )
    raw_secret = confidential_application.plaintext_secret

    persisted_token = Doorkeeper::AccessToken.find(token.id)
    persisted_application = Doorkeeper::Application.find(confidential_application.id)

    assert_equal Digest::SHA256.hexdigest(raw_token), persisted_token[:token]
    assert_equal Digest::SHA256.hexdigest(raw_secret), persisted_application.secret
    assert_not_equal raw_token, persisted_token[:token]
    assert_not_equal raw_secret, persisted_application.secret
    assert_equal persisted_token, Doorkeeper::AccessToken.by_token(raw_token)
    assert_equal persisted_application,
      Doorkeeper::Application.by_uid_and_secret(confidential_application.uid, raw_secret)
  end

  test "access token principal binding cannot be reassigned" do
    token = create_oauth_token(application: @application, user: @user)

    assert_raises(ActiveRecord::ReadonlyAttributeError) do
      token.update!(principal_kind: "project", project_id: @project.id)
    end

    token.reload
    assert_equal "user", token.principal_kind
    assert_nil token.project_id
  end

  test "authorization grant principal binding cannot be reassigned" do
    grant = Doorkeeper::AccessGrant.create!(
      application: @application,
      resource_owner_id: @user.id,
      principal_kind: "user",
      project_id: nil,
      expires_in: 10.minutes.to_i,
      redirect_uri: @application.redirect_uri,
      scopes: "mcp_read"
    )

    assert_raises(ActiveRecord::ReadonlyAttributeError) do
      grant.update!(principal_kind: "project", project_id: @project.id)
    end

    grant.reload
    assert_equal "user", grant.principal_kind
    assert_nil grant.project_id
  end

  test "approved device principal binding cannot be reassigned" do
    grant = OauthDeviceGrant.create!(
      application: @application,
      resource_owner: @user,
      project: @project,
      principal_kind: "project",
      device_code: OauthDeviceGrant.digest_device_code("device-secret"),
      user_code: "ABCDE-23456",
      scopes: "mcp_read",
      expires_at: 10.minutes.from_now,
      approved_at: Time.current
    )

    assert_not grant.update(principal_kind: "user", project: nil)
    assert_includes grant.errors[:principal_kind], "cannot change after approval"
    assert_equal "project", grant.reload.principal_kind
    assert_equal @project, grant.project
  end
end
