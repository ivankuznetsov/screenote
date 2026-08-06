# frozen_string_literal: true

# screenote-edition: self_hosted

require "test_helper"

module Oauth
  class DeviceAuthorizationsControllerTest < ActionDispatch::IntegrationTest
    setup do
      @user = users(:alice)
      @application = create_oauth_application(name: "Screenote CLI")
      @application.update!(scopes: "mcp_read mcp_write")
      Rails.cache.clear
      DeviceAuthorizationRateLimiter.reset!
    end

    teardown do
      Rails.cache.clear
      DeviceAuthorizationRateLimiter.reset!
    end

    test "verification requires authentication and preserves the complete path" do
      codes = initiate_device_authorization

      get "/oauth/device", params: { user_code: codes["user_code"] }

      assert_redirected_to new_session_path
      assert_equal "/oauth/device?user_code=#{CGI.escape(codes['user_code'])}", session[:return_to]
    end

    test "invalid and expired user codes are rejected without authorizing" do
      sign_in(@user)

      get "/oauth/device", params: { user_code: "not-a-code" }
      assert_response :unprocessable_entity
      assert_select "[data-testid='device-code-error']", text: /invalid or expired/i

      get "/oauth/device", params: { user_code: "WRONG-CODE0" }
      assert_response :unprocessable_entity
      assert_select "[data-testid='device-code-error']", text: /invalid or expired/i

      codes = initiate_device_authorization
      grant_for(codes).update_column(:expires_at, 1.second.ago)

      get "/oauth/device", params: { user_code: codes["user_code"] }
      assert_response :unprocessable_entity
      assert_select "[data-testid='device-code-error']", text: /invalid or expired/i
      assert_nil grant_for(codes).resource_owner_id
    end

    test "verification form includes CSRF token and explicit approve and deny controls" do
      codes = initiate_device_authorization
      sign_in(@user)

      previous_forgery_protection = ActionController::Base.allow_forgery_protection
      ActionController::Base.allow_forgery_protection = true
      get "/oauth/device", params: { user_code: codes["user_code"] }

      assert_response :success
      assert_select "form[action='/oauth/device'][method='post']" do
        assert_select "input[name='authenticity_token']"
        assert_select "button[name='decision'][value='approve']"
        assert_select "button[name='decision'][value='deny']"
      end
    ensure
      ActionController::Base.allow_forgery_protection = previous_forgery_protection
    end

    test "GET and POST verification attempts share a rate limit per signed-in user" do
      sign_in(@user)

      5.times do
        get "/oauth/device", params: { user_code: "WRONG-CODE0" }
        assert_response :unprocessable_entity
      end

      5.times do
        post "/oauth/device", params: { user_code: "WRONG-CODE0", decision: "approve" }
        assert_response :unprocessable_entity
      end

      get "/oauth/device", params: { user_code: "WRONG-CODE0" }
      assert_response :too_many_requests
      assert_equal DeviceAuthorizationsController::VERIFICATION_ATTEMPT_WINDOW.to_i.to_s, response.headers["Retry-After"]
    end

    test "invalid-code verification fails closed when the rate-limit counter is unavailable" do
      sign_in(@user)

      with_unavailable_device_rate_limit_store do
        get "/oauth/device", params: { user_code: "WRONG-CODE0" }
      end

      assert_response :service_unavailable
      assert_select "[data-testid='device-code-error']", text: /try again/i
      assert_equal DeviceAuthorizationsController::RATE_LIMITER_RETRY_AFTER.to_s, response.headers["Retry-After"]
      assert_equal "no-store", response.headers["Cache-Control"]
      assert_equal "no-cache", response.headers["Pragma"]
    end

    test "valid-code approval fails closed when the rate-limit counter is unavailable" do
      codes = initiate_device_authorization
      sign_in(@user)

      with_unavailable_device_rate_limit_store do
        post "/oauth/device", params: { user_code: codes["user_code"], decision: "approve" }
      end

      assert_response :service_unavailable
      assert_select "[data-testid='device-code-error']", text: /try again/i
      assert_equal DeviceAuthorizationsController::RATE_LIMITER_RETRY_AFTER.to_s, response.headers["Retry-After"]
      assert_equal "no-store", response.headers["Cache-Control"]
      assert_equal "no-cache", response.headers["Pragma"]

      grant = grant_for(codes).reload
      assert_nil grant.resource_owner_id
      assert_nil grant.approved_at
    end

    test "verification page accepts code entry before a code is supplied" do
      sign_in(@user)

      get "/oauth/device"

      assert_response :success
      assert_select "form[action='/oauth/device'][method='get']"
      assert_select "input[name='user_code']"
    end

    test "update rejects a missing decision without mutating the grant" do
      codes = initiate_device_authorization
      sign_in(@user)

      post "/oauth/device", params: { user_code: codes["user_code"] }

      assert_response :unprocessable_entity
      assert_equal "Choose Approve or Deny.", response.body
      grant = grant_for(codes).reload
      assert_nil grant.resource_owner_id
      assert_nil grant.approved_at
      assert_nil grant.denied_at
    end

    test "update rejects a missing user code instead of returning an empty success" do
      sign_in(@user)

      post "/oauth/device", params: { decision: "approve" }

      assert_response :unprocessable_entity
      assert_select "[data-testid='device-code-error']", text: /invalid or expired/i
    end

    test "account approval rejects authority lost after code lookup" do
      codes = initiate_device_authorization
      sign_in(@user)
      expected_user = @user
      expected_grant = grant_for(codes)
      replacement = lambda do |user:, credential:, &block|
        raise "unexpected user" unless user == expected_user
        raise "unexpected grant" unless credential == expected_grant

        block.call(false, nil)
      end

      with_singleton_method(PrincipalBinding, :with_locked_user, replacement) do
        post "/oauth/device", params: { user_code: codes["user_code"], decision: "approve" }
      end

      assert_response :unprocessable_entity
      assert_select "[data-testid='device-code-error']", text: /invalid or expired/i
      assert_nil grant_for(codes).reload.approved_at
    end

    test "project approval rejects a grant consumed after authority locking" do
      codes = initiate_device_authorization
      sign_in(@user)
      project = @user.projects.first!
      expected_user = @user
      expected_project_id = project.id.to_s
      replacement = lambda do |user:, project_id:, credential:, &block|
        raise "unexpected user" unless user == expected_user
        raise "unexpected project" unless expected_project_id == project_id.to_s

        credential.update_column(:denied_at, Time.current)
        block.call(true)
      end

      with_singleton_method(PrincipalBinding, :with_locked_project, replacement) do
        post "/oauth/device", params: {
          user_code: codes["user_code"],
          decision: "approve",
          principal_project_id: project.id
        }
      end

      assert_response :unprocessable_entity
      assert_select "[data-testid='device-code-error']", text: /invalid or expired/i
      assert_nil grant_for(codes).reload.approved_at
    end

    test "denial rejects a grant consumed between lookup and row lock" do
      codes = initiate_device_authorization
      sign_in(@user)
      grant = grant_for(codes)
      grant.define_singleton_method(:with_lock) do |&block|
        update_column(:expires_at, 1.second.ago)
        block.call
      end

      with_singleton_method(OauthDeviceGrant, :find_by, ->(**) { grant }) do
        post "/oauth/device", params: { user_code: codes["user_code"], decision: "deny" }
      end

      assert_response :unprocessable_entity
      assert_select "[data-testid='device-code-error']", text: /invalid or expired/i
      assert_nil grant.reload.denied_at
    end

    private

    def initiate_device_authorization
      post "/oauth/authorize_device", params: {
        client_id: @application.uid,
        scope: "mcp_read mcp_write"
      }
      response.parsed_body
    end

    def grant_for(codes)
      OauthDeviceGrant.find_by_plaintext_device_code(codes["device_code"])
    end

    def with_singleton_method(object, name, implementation)
      original = object.method(name)
      object.define_singleton_method(name, implementation)
      yield
    ensure
      object.define_singleton_method(name, original) if original
    end
  end
end
