# frozen_string_literal: true

require "test_helper"

module Api
  class BearerAuthenticatorTest < ActiveSupport::TestCase
    ALICE_TOKEN = "sk_proj_test_alice_key_000000000000000000000000"
    REVOKED_KEY_TOKEN = "sk_proj_test_alice_revoked_00000000000000000000"

    test "returns nil for a blank token" do
      assert_nil Api::BearerAuthenticator.call(nil)
      assert_nil Api::BearerAuthenticator.call("")
    end

    test "authenticates an active api key and never consults oauth" do
      result = Api::BearerAuthenticator.call(ALICE_TOKEN)

      assert result.api_key?
      assert_not result.oauth?
      assert_equal api_keys(:alice_key), result.api_key
      assert_nil result.oauth_token
      assert_nil result.user
      assert_equal users(:alice), result.issuer
      assert_equal projects(:alice_project), result.project
      assert_equal %w[mcp_read mcp_write], result.scopes
    end

    test "touches last_used_at on api key authentication" do
      api_keys(:alice_key).update_column(:last_used_at, 1.hour.ago)
      previous = api_keys(:alice_key).last_used_at

      Api::BearerAuthenticator.call(ALICE_TOKEN)

      assert api_keys(:alice_key).reload.last_used_at > previous
    end

    test "returns nil for a revoked api key" do
      assert_nil Api::BearerAuthenticator.call(REVOKED_KEY_TOKEN)
    end

    test "active api key fails closed when its issuer is suspended" do
      key = api_keys(:alice_key)
      previous_last_used_at = key.last_used_at
      users(:alice).update!(access_status: :suspended)

      assert_nil Api::BearerAuthenticator.call(ALICE_TOKEN)
      assert_equal previous_last_used_at, key.reload.last_used_at
    end

    test "authenticates a valid oauth access token" do
      token = create_oauth_token(application: create_oauth_application, user: users(:alice), scopes: "mcp_read")

      result = Api::BearerAuthenticator.call(token.token)

      assert result.oauth?
      assert_not result.api_key?
      assert_equal token, result.oauth_token
      assert_equal users(:alice), result.user
      assert_nil result.project
      assert_equal [ "mcp_read" ], result.scopes
    end

    test "returns nil for a revoked oauth token" do
      token = create_oauth_token(application: create_oauth_application, user: users(:alice), revoked_at: 1.minute.ago)

      assert_nil Api::BearerAuthenticator.call(token.token)
    end

    test "returns nil for an expired oauth token" do
      token = create_oauth_token(application: create_oauth_application, user: users(:alice), expires_in: -1.minute)

      assert_nil Api::BearerAuthenticator.call(token.token)
    end

    test "returns nil for an unknown token" do
      assert_nil Api::BearerAuthenticator.call("not-a-real-token")
    end

    test "returns nil when the oauth token resource owner no longer exists" do
      token = create_oauth_token(application: create_oauth_application, user: users(:alice))

      # A DB-level cascade keeps tokens from truly outliving their user, so
      # override the lookup to exercise the defensive orphaned-resource_owner_id
      # branch (find_by returning nil for a live token).
      User.define_singleton_method(:find_by) { |*| nil }
      begin
        assert_nil Api::BearerAuthenticator.call(token.token)
      ensure
        User.singleton_class.send(:remove_method, :find_by)
      end
    end

    test "authenticates project oauth only while the resource owner remains a member" do
      user = users(:bob)
      project = projects(:alice_project)
      token = create_oauth_token(
        application: create_oauth_application,
        user: user,
        project: project,
        scopes: "mcp_write"
      )

      result = Api::BearerAuthenticator.call(token.token)

      assert_predicate result, :project_principal?
      assert_equal project, result.project
      assert result.write?
      assert_not result.read?

      project.project_memberships.find_by!(user: user).delete
      assert_nil Api::BearerAuthenticator.call(token.token)
    end
  end
end
