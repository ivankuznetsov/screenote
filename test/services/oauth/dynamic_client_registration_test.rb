# frozen_string_literal: true

require "test_helper"

module Oauth
  class DynamicClientRegistrationTest < ActiveSupport::TestCase
    test "cleanup expires an unused dynamic client and its stale grant" do
      application = register("Unused client")
      grant = Doorkeeper::AccessGrant.create!(
        application: application,
        resource_owner_id: users(:alice).id,
        principal_kind: "user",
        project_id: nil,
        expires_in: 1,
        redirect_uri: application.redirect_uri,
        scopes: "mcp_read",
        created_at: 2.days.ago
      )
      application.update_columns(created_at: 2.days.ago, last_used_at: 2.days.ago)

      assert_difference [ "Doorkeeper::Application.count", "Doorkeeper::AccessGrant.count" ], -1 do
        assert_equal 1, DynamicClientRegistration.cleanup_unused!
      end

      assert_not Doorkeeper::Application.exists?(application.id)
      assert_not Doorkeeper::AccessGrant.exists?(grant.id)
    end

    test "cleanup retains a stale client while it has an active bearer credential" do
      application = register("Active client")
      token = create_oauth_token(application: application, user: users(:alice))
      application.update_columns(created_at: 2.days.ago, last_used_at: 2.days.ago)

      assert_no_difference [ "Doorkeeper::Application.count", "Doorkeeper::AccessToken.count" ] do
        assert_equal 0, DynamicClientRegistration.cleanup_unused!
      end

      assert Doorkeeper::Application.exists?(application.id)
      assert Doorkeeper::AccessToken.exists?(token.id)
    end

    test "global saturation preserves idempotent registration but rejects a new fingerprint" do
      existing = register("Capacity client")
      limit = Doorkeeper::Application.where(dynamic: true).count

      with_maximum_dynamic_clients(limit) do
        replay = DynamicClientRegistration.call(
          client_name: existing.name,
          redirect_uris: existing.redirect_uri.split("\n")
        )

        assert_not replay.created
        assert_equal existing.id, replay.application.id
        assert_raises(DynamicClientRegistration::CapacityExceeded) do
          register("Over-capacity client")
        end
      end
    end

    private

    def register(name)
      DynamicClientRegistration.call(
        client_name: name,
        redirect_uris: [ "http://127.0.0.1:4567/callback" ]
      ).application
    end

    def with_maximum_dynamic_clients(limit)
      singleton_class = DynamicClientRegistration.singleton_class
      original = DynamicClientRegistration.method(:maximum_dynamic_clients)
      singleton_class.define_method(:maximum_dynamic_clients) { limit }
      yield
    ensure
      singleton_class&.define_method(:maximum_dynamic_clients, original)
    end
  end
end
