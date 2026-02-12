# frozen_string_literal: true

require "test_helper"

class ApiKeyTest < ActiveSupport::TestCase
  setup do
    @project = projects(:alice_project)
    @api_key = api_keys(:alice_key)
  end

  test "generates token digest on create" do
    key = @project.api_keys.create!(name: "New Key")
    assert key.token_digest.present?, "Token digest should be generated"
    assert key.token_prefix.present?, "Token prefix should be generated"
    assert key.raw_token.start_with?("sk_proj_"), "Raw token should start with sk_proj_ prefix"
    assert_equal Digest::SHA256.hexdigest(key.raw_token), key.token_digest
  end

  test "raw_token is only available after create" do
    key = @project.api_keys.create!(name: "New Key")
    raw = key.raw_token
    assert raw.present?, "Raw token should be available right after create"

    reloaded = ApiKey.find(key.id)
    assert_nil reloaded.raw_token, "Raw token should not be available after reload"
  end

  test "find_by_token returns correct key" do
    token = "sk_proj_test_alice_key_000000000000000000000000"
    found = ApiKey.find_by_token(token)
    assert_equal @api_key, found
  end

  test "find_by_token returns nil for unknown token" do
    assert_nil ApiKey.find_by_token("sk_proj_nonexistent")
  end

  test "find_by_token returns nil for blank token" do
    assert_nil ApiKey.find_by_token("")
    assert_nil ApiKey.find_by_token(nil)
  end

  test "requires name" do
    key = @project.api_keys.build(name: "")
    assert_not key.valid?, "Key without name should be invalid"
    assert key.errors[:name].any?
  end

  test "token digest must be unique" do
    existing_digest = @api_key.token_digest
    duplicate = @project.api_keys.build(name: "Dupe")
    duplicate.token_digest = existing_digest
    assert_not duplicate.valid?, "Duplicate token digest should be invalid"
    assert duplicate.errors[:token_digest].any?
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

  test "touch_last_used! is throttled within 5 minutes" do
    @api_key.update_column(:last_used_at, 2.minutes.ago)
    timestamp_before = @api_key.reload.last_used_at

    @api_key.touch_last_used!

    assert_equal timestamp_before, @api_key.reload.last_used_at,
      "Should not update last_used_at within 5 minute throttle window"
  end

  test "touch_last_used! updates when last_used_at is nil" do
    @api_key.update_column(:last_used_at, nil)
    @api_key.reload

    @api_key.touch_last_used!

    assert @api_key.reload.last_used_at.present?, "Should update last_used_at when nil"
  end

  test "revoke! is idempotent" do
    @api_key.revoke!
    first_revoked_at = @api_key.revoked_at

    @api_key.revoke!

    assert_equal first_revoked_at, @api_key.revoked_at,
      "Revoking twice should not change revoked_at"
  end

  test "name cannot exceed 255 characters" do
    key = @project.api_keys.build(name: "a" * 256)
    assert_not key.valid?, "Name exceeding 255 chars should be invalid"
    assert key.errors[:name].any?
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
