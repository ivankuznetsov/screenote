# frozen_string_literal: true

require "test_helper"

module Oauth
  class DynamicClientAuthorizationQuotaTest < ActiveSupport::TestCase
    test "rejects a new dynamic client after the user reaches the active-client limit" do
      user = users(:alice)
      first = dynamic_application("First quota client")
      second = dynamic_application("Second quota client")
      third = dynamic_application("Third quota client")
      create_refresh_credential(user:, application: first)
      create_refresh_credential(user:, application: second)
      yielded = false

      with_maximum_authorized_clients(2) do
        error = assert_raises(DynamicClientAuthorizationQuota::Exceeded) do
          DynamicClientAuthorizationQuota.authorize(user:, application: third) { yielded = true }
        end

        assert_match(/2 active dynamic clients/, error.message)
      end

      assert_not yielded
    end

    test "allows reauthorization of a dynamic client already counted for the user" do
      user = users(:alice)
      application = dynamic_application("Existing quota client")
      create_refresh_credential(user:, application:)

      result = with_maximum_authorized_clients(1) do
        DynamicClientAuthorizationQuota.authorize(user:, application:) { :authorized }
      end

      assert_equal :authorized, result
    end

    test "revoked and expired credentials release capacity" do
      user = users(:alice)
      revoked_application = dynamic_application("Revoked quota client")
      expired_application = dynamic_application("Expired quota client")
      next_application = dynamic_application("Replacement quota client")
      create_refresh_credential(user:, application: revoked_application, revoked_at: Time.current)
      create_access_credential(user:, application: expired_application, created_at: 2.hours.ago, expires_in: 1)
      Doorkeeper::AccessGrant.create!(
        application: expired_application,
        resource_owner_id: user.id,
        principal_kind: "user",
        project_id: nil,
        expires_in: 1,
        redirect_uri: expired_application.redirect_uri,
        scopes: "mcp_read",
        created_at: 2.hours.ago
      )

      result = with_maximum_authorized_clients(1) do
        DynamicClientAuthorizationQuota.authorize(user:, application: next_application) { :authorized }
      end

      assert_equal :authorized, result
    end

    test "an approved unexpired device credential consumes capacity" do
      user = users(:alice)
      application = dynamic_application("Approved device quota client")
      next_application = dynamic_application("Blocked device quota client")
      OauthDeviceGrant.create!(
        application:,
        resource_owner: user,
        device_code: OauthDeviceGrant.digest_device_code(SecureRandom.urlsafe_base64(32)),
        user_code: unique_user_code,
        scopes: "mcp_read",
        expires_at: 10.minutes.from_now,
        principal_kind: "user",
        approved_at: Time.current
      )

      with_maximum_authorized_clients(1) do
        assert_raises(DynamicClientAuthorizationQuota::Exceeded) do
          DynamicClientAuthorizationQuota.authorize(user:, application: next_application) { flunk }
        end
      end
    end

    test "an unexpired access token without refresh consumes capacity" do
      user = users(:alice)
      application = dynamic_application("Access token quota client")
      next_application = dynamic_application("Blocked access token quota client")
      create_access_credential(user:, application:, created_at: Time.current, expires_in: 1.hour)

      with_maximum_authorized_clients(1) do
        assert_raises(DynamicClientAuthorizationQuota::Exceeded) do
          DynamicClientAuthorizationQuota.authorize(user:, application: next_application) { flunk }
        end
      end
    end

    test "does not apply the public-client quota to a managed application" do
      user = users(:alice)
      application = create_oauth_application(name: "Managed OAuth client")

      result = with_maximum_authorized_clients(0) do
        DynamicClientAuthorizationQuota.authorize(user:, application:) { :authorized }
      end

      assert_equal :authorized, result
    end

    private

    def dynamic_application(name)
      create_oauth_application(name:).tap { |application| application.update!(dynamic: true) }
    end

    def create_refresh_credential(user:, application:, revoked_at: nil)
      Doorkeeper::AccessToken.create!(
        application:,
        resource_owner_id: user.id,
        principal_kind: "user",
        scopes: "mcp_read",
        expires_in: 1.hour,
        refresh_token: Digest::SHA256.hexdigest(SecureRandom.urlsafe_base64(32)),
        revoked_at:
      )
    end

    def create_access_credential(user:, application:, created_at:, expires_in:)
      Doorkeeper::AccessToken.create!(
        application:,
        resource_owner_id: user.id,
        principal_kind: "user",
        scopes: "mcp_read",
        expires_in:,
        created_at:
      )
    end

    def unique_user_code
      characters = SecureRandom.alphanumeric(10).upcase
      "#{characters.first(5)}-#{characters.last(5)}"
    end

    def with_maximum_authorized_clients(limit)
      singleton_class = DynamicClientAuthorizationQuota.singleton_class
      original = DynamicClientAuthorizationQuota.method(:maximum_authorized_clients_per_user)
      singleton_class.define_method(:maximum_authorized_clients_per_user) { limit }
      singleton_class.send(:private, :maximum_authorized_clients_per_user)
      yield
    ensure
      singleton_class&.define_method(:maximum_authorized_clients_per_user, original)
      singleton_class&.send(:private, :maximum_authorized_clients_per_user)
    end
  end
end
