# frozen_string_literal: true

# screenote-edition: self_hosted

require "test_helper"
require_relative "../../support/instance_administration_test_helper"

module Instance
  class AccountsControllerTest < ActionDispatch::IntegrationTest
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

    test "administrator sees identity status and actions without project content" do
      get instance_accounts_path

      assert_response :success
      assert_private_headers
      assert_select "h1", text: "Instance administration"
      assert_select "[data-testid='instance-account']", minimum: User.count
      assert_select ".instance-account__email", text: @target.email
      assert_select "form[action='#{suspend_instance_account_path(@target)}']"
      assert_select "form[action='#{issue_recovery_instance_account_path(@target)}']"
      assert_not_includes response.body, projects(:bob_project).name
      assert_not_includes response.body, projects(:alice_project).description
    end

    test "recovery link is rendered once in a private response and never placed in session" do
      assert_difference -> { AuthenticationToken.account_recovery.count }, 1 do
        post issue_recovery_instance_account_path(@target),
          headers: { "Accept" => "text/vnd.turbo-stream.html" }
      end

      assert_response :success
      assert_equal "text/vnd.turbo-stream.html", response.media_type
      assert_select "turbo-stream[action='replace'][target='recovery-reveal-container']"
      assert_private_headers
      assert_select "[data-testid='recovery-reveal'][data-turbo-temporary]"
      assert_select "[data-testid='recovery-link']", count: 1
      assert_select "[data-controller='clipboard'] [data-action='clipboard#copy']", text: "Copy recovery link"
      assert_select "[data-clipboard-target='status'][role='status']"
      link = css_select("[data-testid='recovery-link']").first["value"]
      assert_match(/#/, link)
      assert_nil session[:authentication_link]
      assert_not_includes cookies.to_s, URI.parse(link).fragment

      get instance_accounts_path
      assert_response :success
      assert_select "[data-testid='recovery-link']", count: 0
    end

    test "html recovery issuance renders the accounts page with the one-time link" do
      assert_difference -> { AuthenticationToken.account_recovery.count }, 1 do
        post issue_recovery_instance_account_path(@target)
      end

      assert_response :success
      assert_equal "text/html", response.media_type
      assert_private_headers
      assert_select "[data-testid='recovery-link']", count: 1
    end

    test "html recovery issuance does not supersede a link when account loading is unavailable" do
      existing = create_recovery_token(subject: @target, issuer: @administrator)
      unavailable = InstanceAccounts::List::Result.new(
        status: :unavailable,
        accounts: [],
        administrator_id: nil
      )

      with_singleton_method_stub(InstanceAccounts::List, :call, ->(**) { unavailable }) do
        assert_no_difference -> { AuthenticationToken.account_recovery.count } do
          post issue_recovery_instance_account_path(@target)
        end
      end

      assert_response :service_unavailable
      assert_equal "60", response.headers["Retry-After"]
      assert_includes response.body, "temporarily unavailable"
      assert_select "[data-testid='recovery-link']", count: 0
      assert existing.token.reload.outstanding?
    end

    test "turbo recovery issuance renders directly without loading the account list" do
      list_calls = 0
      unavailable = InstanceAccounts::List::Result.new(
        status: :unavailable,
        accounts: [],
        administrator_id: nil
      )

      with_singleton_method_stub(InstanceAccounts::List, :call, ->(**) { list_calls += 1; unavailable }) do
        assert_difference -> { AuthenticationToken.account_recovery.count }, 1 do
          post issue_recovery_instance_account_path(@target),
            headers: { "Accept" => "text/vnd.turbo-stream.html" }
        end
      end

      assert_response :success
      assert_equal 0, list_calls
      assert_select "[data-testid='recovery-link']", count: 1
    end

    test "suspension revokes access and keeps the current administrator active" do
      post suspend_instance_account_path(@target)

      assert_redirected_to instance_accounts_path
      assert @target.reload.suspended?
      assert @administrator.reload.active?
      assert_equal @administrator, @installation.reload.administrator
    end

    test "restore and credential revocation actions report their successful outcomes" do
      @target.update!(access_status: :suspended)

      post restore_instance_account_path(@target)
      assert_redirected_to instance_accounts_path
      assert_equal "Account restored. New sign-in is required.", flash[:notice]
      assert @target.reload.active?

      post revoke_credentials_instance_account_path(@target)
      assert_redirected_to instance_accounts_path
      assert_equal "Account credentials revoked.", flash[:notice]
      assert @target.reload.active?
    end

    test "failed recovery issuance reports that a suspended account must be restored" do
      @target.update!(access_status: :suspended)

      post issue_recovery_instance_account_path(@target)

      assert_redirected_to instance_accounts_path
      assert_equal "Restore this account before issuing recovery.", flash[:alert]
      assert_not AuthenticationToken.account_recovery.where(user: @target).exists?
    end

    test "mutation result statuses map to stable redirects and messages" do
      expectations = {
        already_suspended: [ instance_accounts_path, :notice, "Account is already suspended." ],
        already_active: [ instance_accounts_path, :notice, "Account is already active." ],
        cannot_suspend_administrator: [
          instance_accounts_path,
          :alert,
          "Transfer instance administration before suspending this account."
        ],
        not_found: [ instance_accounts_path, :alert, "Account no longer exists." ],
        forbidden: [ dashboard_path, :alert, "Not authorized." ],
        inactive_target: [ instance_accounts_path, :alert, "Restore this account before issuing recovery." ]
      }

      expectations.each do |status, (destination, flash_type, message)|
        result = instance_result(status)
        with_singleton_method_stub(InstanceAccounts::Suspend, :call, ->(**) { result }) do
          post suspend_instance_account_path(@target)
        end

        assert_redirected_to destination
        assert_equal message, flash[flash_type]
      end
    end

    test "busy and invalid mutations render the accounts page with the appropriate status" do
      {
        retryable_busy: [ :conflict, "Another account change is in progress. Please retry." ],
        invalid: [ :unprocessable_content, "The account change could not be completed." ]
      }.each do |result_status, (response_status, message)|
        result = instance_result(result_status)
        with_singleton_method_stub(InstanceAccounts::Suspend, :call, ->(**) { result }) do
          post suspend_instance_account_path(@target)
        end

        assert_response response_status
        assert_private_headers
        assert_select ".flash--alert", text: message
        assert_select ".instance-account__email", text: @target.email
      end
    end

    test "unavailable mutations return a retryable service unavailable response" do
      mutation = instance_result(:unavailable)

      with_singleton_method_stub(InstanceAccounts::Suspend, :call, ->(**) { mutation }) do
        post suspend_instance_account_path(@target)
      end

      assert_response :service_unavailable
      assert_equal "60", response.headers["Retry-After"]
      assert_private_headers
      assert_select ".flash--alert", text: "Instance administration is temporarily unavailable."
      assert_select ".instance-account__email", text: @target.email
    end

    test "unexpected mutation statuses fail closed as retryable service unavailability" do
      mutation = instance_result(:unexpected_failure)

      with_singleton_method_stub(InstanceAccounts::Suspend, :call, ->(**) { mutation }) do
        post suspend_instance_account_path(@target)
      end

      assert_response :service_unavailable
      assert_equal "60", response.headers["Retry-After"]
      assert_private_headers
      assert_select ".flash--alert", text: "Instance administration is temporarily unavailable."
      assert_select ".instance-account__email", text: @target.email
    end

    test "mutation error rendering returns service unavailable if the account list is unavailable" do
      mutation = instance_result(:invalid)
      unavailable_list = InstanceAccounts::List::Result.new(
        status: :unavailable,
        accounts: [],
        administrator_id: nil
      )

      with_singleton_method_stub(InstanceAccounts::Suspend, :call, ->(**) { mutation }) do
        with_singleton_method_stub(InstanceAccounts::List, :call, ->(**) { unavailable_list }) do
          post suspend_instance_account_path(@target)
        end
      end

      assert_response :service_unavailable
      assert_equal "60", response.headers["Retry-After"]
      assert_includes response.body, "temporarily unavailable"
      assert_not_includes response.body, "Not authorized."
    end

    test "mutation error rendering preserves forbidden account-list results" do
      mutation = instance_result(:invalid)
      forbidden_list = InstanceAccounts::List::Result.new(
        status: :forbidden,
        accounts: [],
        administrator_id: nil
      )

      with_singleton_method_stub(InstanceAccounts::Suspend, :call, ->(**) { mutation }) do
        with_singleton_method_stub(InstanceAccounts::List, :call, ->(**) { forbidden_list }) do
          post suspend_instance_account_path(@target)
        end
      end

      assert_redirected_to dashboard_path
      assert_equal "Not authorized.", flash[:alert]
      assert_nil response.headers["Retry-After"]
    end

    test "non administrator cannot list accounts and denial is audited" do
      delete session_path
      sign_in @target

      assert_difference -> { InstallationAuditEvent.where(event_type: "instance_action_denied").count }, 1 do
        get instance_accounts_path
      end

      assert_redirected_to dashboard_path
      assert_equal "Not authorized.", flash[:alert]
    end

    test "transfer removes privileged navigation and action authority immediately" do
      post instance_administrator_transfer_path, params: { administrator_id: @target.id }

      assert_redirected_to dashboard_path
      assert_equal @target, @installation.reload.administrator

      get instance_accounts_path
      assert_redirected_to dashboard_path
      follow_redirect!
      assert_select "a", text: "Instance administration", count: 0
    end

    private

    def instance_routes_drawn?
      Rails.application.routes.url_helpers.respond_to?(:instance_accounts_path)
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
