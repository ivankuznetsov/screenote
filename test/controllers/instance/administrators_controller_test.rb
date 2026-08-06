# frozen_string_literal: true

# screenote-edition: self_hosted

require "test_helper"
require_relative "../../support/instance_administration_test_helper"

module Instance
  class AdministratorsControllerTest < ActionDispatch::IntegrationTest
    include InstanceAdministrationTestHelper
    self.use_transactional_tests = false

    setup do
      skip "instance administration routes are absent in SaaS mode" unless instance_routes_drawn?

      @administrator = users(:alice)
      @target = users(:bob)
      @installation = prepare_claimed_installation(administrator: @administrator)
      @target.update!(access_status: :active)
      sign_in @administrator
    end

    teardown do
      return unless instance_routes_drawn?

      AuthenticationToken.delete_all
      InstallationAuditEvent.delete_all
      Installation.delete_all
      Current.reset
    end

    test "administrator transfers authority to an active account" do
      post instance_administrator_transfer_path, params: { administrator_id: @target.id }

      assert_redirected_to dashboard_path
      assert_equal "Instance administration transferred.", flash[:notice]
      assert_equal @target, @installation.reload.administrator
      assert_private_headers
    end

    test "transferring to the current administrator is idempotent" do
      post instance_administrator_transfer_path, params: { administrator_id: @administrator.id }

      assert_redirected_to instance_accounts_path
      assert_equal "This account is already the administrator.", flash[:notice]
      assert_equal @administrator, @installation.reload.administrator
    end

    test "administration cannot be transferred to an inactive account" do
      @target.update!(access_status: :suspended)

      post instance_administrator_transfer_path, params: { administrator_id: @target.id }

      assert_redirected_to instance_accounts_path
      assert_equal "Restore the account before transferring administration.", flash[:alert]
      assert_equal @administrator, @installation.reload.administrator
    end

    test "a missing transfer target reports that the account no longer exists" do
      post instance_administrator_transfer_path, params: { administrator_id: 0 }

      assert_redirected_to instance_accounts_path
      assert_equal "Account no longer exists.", flash[:alert]
      assert_equal @administrator, @installation.reload.administrator
    end

    test "a stale administrator loses transfer authority immediately" do
      post instance_administrator_transfer_path, params: { administrator_id: @target.id }
      assert_equal @target, @installation.reload.administrator

      post instance_administrator_transfer_path, params: { administrator_id: @administrator.id }

      assert_redirected_to dashboard_path
      assert_equal "Instance administration changed.", flash[:alert]
      assert_equal @target, @installation.reload.administrator
    end

    test "a concurrently suspended actor receives the generic authority-changed response" do
      result = instance_result(:forbidden)

      with_singleton_method_stub(Installations::TransferAdministrator, :call, ->(**) { result }) do
        post instance_administrator_transfer_path, params: { administrator_id: @target.id }
      end

      assert_redirected_to dashboard_path
      assert_equal "Instance administration changed.", flash[:alert]
    end

    test "busy transfers tell the administrator to retry" do
      result = instance_result(:retryable_busy)

      with_singleton_method_stub(Installations::TransferAdministrator, :call, ->(**) { result }) do
        post instance_administrator_transfer_path, params: { administrator_id: @target.id }
      end

      assert_redirected_to instance_accounts_path
      assert_equal "Another administrator change is in progress. Please retry.", flash[:alert]
    end

    test "invalid and unavailable transfer results fail closed" do
      %i[invalid unavailable].each do |status|
        result = instance_result(status)

        with_singleton_method_stub(Installations::TransferAdministrator, :call, ->(**) { result }) do
          post instance_administrator_transfer_path, params: { administrator_id: @target.id }
        end

        assert_redirected_to instance_accounts_path
        assert_equal "Administration could not be transferred.", flash[:alert]
      end
    end

    private

    def instance_routes_drawn?
      Rails.application.routes.url_helpers.respond_to?(:instance_administrator_transfer_path)
    end

    def assert_private_headers
      assert_includes response.headers.fetch("Cache-Control"), "no-store"
      assert_equal "no-referrer", response.headers["Referrer-Policy"]
      assert_equal "noindex, nofollow", response.headers["X-Robots-Tag"]
    end

    def instance_result(status)
      InstanceAdministration::Result.new(status: status)
    end
  end
end
