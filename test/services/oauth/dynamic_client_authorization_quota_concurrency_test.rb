# frozen_string_literal: true

require "test_helper"

module Oauth
  class DynamicClientAuthorizationQuotaConcurrencyTest < ActiveSupport::TestCase
    self.use_transactional_tests = false

    setup do
      suffix = SecureRandom.hex(8)
      @user = User.create!(
        email: "oauth-quota-#{suffix}@example.test",
        password: "password123",
        password_confirmation: "password123",
        confirmed_at: Time.current
      )
      @applications = 2.times.map do |index|
        create_oauth_application(name: "Concurrent quota #{index} #{suffix}").tap do |application|
          application.update!(dynamic: true)
        end
      end
    end

    teardown do
      application_ids = @applications.map(&:id)
      OauthDeviceGrant.where(application_id: application_ids).delete_all
      Doorkeeper::AccessGrant.where(application_id: application_ids).delete_all
      Doorkeeper::AccessToken.where(application_id: application_ids).delete_all
      Doorkeeper::Application.where(id: application_ids).delete_all
      @user&.destroy!
    end

    test "concurrent first authorizations cannot exceed the per-user limit" do
      ready = Queue.new
      start = Queue.new
      results = Queue.new

      with_maximum_authorized_clients(1) do
        threads = @applications.map do |application|
          Thread.new do
            ActiveRecord::Base.connection_pool.with_connection do
              ready << true
              start.pop
              user = User.find(@user.id)
              client = Doorkeeper::Application.find(application.id)
              DynamicClientAuthorizationQuota.authorize(user:, application: client) do
                Doorkeeper::AccessGrant.create!(
                  application: client,
                  resource_owner_id: user.id,
                  principal_kind: "user",
                  project_id: nil,
                  expires_in: 10.minutes.to_i,
                  redirect_uri: client.redirect_uri,
                  scopes: "mcp_read"
                )
              end
              results << :authorized
            rescue DynamicClientAuthorizationQuota::Exceeded
              results << :quota_exceeded
            rescue StandardError => error
              results << error
            end
          ensure
            ActiveRecord::Base.connection_pool.release_connection
          end
        end

        2.times { ready.pop }
        2.times { start << true }
        threads.each(&:join)
      end

      outcomes = 2.times.map { results.pop }
      assert outcomes.none?(Exception), -> { outcomes.grep(Exception).map(&:full_message).join("\n") }
      assert_equal %i[authorized quota_exceeded], outcomes.sort
      assert_equal 1, Doorkeeper::AccessGrant.where(resource_owner_id: @user.id, revoked_at: nil).count
    end

    private

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
