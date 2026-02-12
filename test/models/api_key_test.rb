# frozen_string_literal: true

require "test_helper"

class ApiKeyTest < ActiveSupport::TestCase
  setup do
    @project = projects(:alice_project)
    @api_key = api_keys(:alice_key)
  end

  test "generates token on create" do
    key = @project.api_keys.create!(name: "New Key")
    assert key.token.present?, "Token should be generated"
    assert key.token.start_with?("sk_proj_"), "Token should start with sk_proj_ prefix"
  end

  test "does not overwrite existing token" do
    key = @project.api_keys.build(name: "Custom", token: "sk_proj_custom_token")
    key.save!
    assert_equal "sk_proj_custom_token", key.token
  end

  test "requires name" do
    key = @project.api_keys.build(name: "")
    assert_not key.valid?, "Key without name should be invalid"
    assert key.errors[:name].any?
  end

  test "token must be unique" do
    duplicate = @project.api_keys.build(name: "Dupe", token: @api_key.token)
    assert_not duplicate.valid?, "Duplicate token should be invalid"
    assert duplicate.errors[:token].any?
  end

  test "active scope excludes revoked keys" do
    active_keys = ApiKey.active.where(project: @project)
    assert_includes active_keys, api_keys(:alice_key)
    assert_not_includes active_keys, api_keys(:alice_key_revoked)
  end

  test "revoked scope includes only revoked keys" do
    revoked_keys = ApiKey.revoked.where(project: @project)
    assert_includes revoked_keys, api_keys(:alice_key_revoked)
    assert_not_includes revoked_keys, api_keys(:alice_key)
  end

  test "revoke! sets revoked_at" do
    assert_nil @api_key.revoked_at
    @api_key.revoke!
    assert @api_key.revoked?, "Key should be revoked"
    assert @api_key.revoked_at.present?
  end

  test "touch_last_used! updates timestamp" do
    old_time = @api_key.last_used_at
    @api_key.touch_last_used!
    assert @api_key.reload.last_used_at > old_time, "last_used_at should be updated"
  end

  test "belongs to project" do
    assert_equal @project, @api_key.project
  end

  test "destroyed with project" do
    assert_difference "ApiKey.count", -2 do
      @project.destroy!
    end
  end
end
