# frozen_string_literal: true

require "test_helper"

class OauthDeviceFlowTest < ActionDispatch::IntegrationTest
  DEVICE_GRANT_TYPE = "urn:ietf:params:oauth:grant-type:device_code"

  setup do
    @user = users(:alice)
    @project = projects(:alice_project)
    @foreign_project = projects(:bob_project)
    @application = create_oauth_application(name: "Screenote CLI")
    @application.update!(scopes: "mcp_read mcp_write")
    Rails.cache.clear
    Oauth::DeviceAuthorizationRateLimiter.reset!
  end

  teardown do
    Rails.cache.clear
    Oauth::DeviceAuthorizationRateLimiter.reset!
  end

  test "device authorization returns expiring non-cacheable codes and stores only a digest" do
    response_body = initiate_device_authorization

    assert_response :success
    assert_equal 600, response_body["expires_in"]
    assert_equal 5, response_body["interval"]
    assert_match(/\A[A-Z\d]{5}-[A-Z\d]{5}\z/, response_body["user_code"])
    assert response_body["device_code"].present?
    assert_equal "#{Screenote::Deployment.current.base_url}/oauth/device", response_body["verification_uri"]
    assert_includes response_body["verification_uri_complete"], "user_code="
    assert_includes response.headers["Cache-Control"], "no-store"
    assert_equal "no-cache", response.headers["Pragma"]

    grant = OauthDeviceGrant.find_by_plaintext_device_code(response_body["device_code"])
    assert grant.present?
    assert_not_equal response_body["device_code"], grant.device_code
    assert_equal Digest::SHA256.hexdigest(response_body["device_code"]), grant.device_code
    assert_equal "mcp_read mcp_write", grant.scopes
    assert_in_delta OauthDeviceGrant::DEFAULT_EXPIRES_IN, grant.expires_at - grant.created_at, 1
  end

  test "device authorization rejects unknown scopes without creating a grant" do
    assert_no_difference "OauthDeviceGrant.count" do
      initiate_device_authorization(scope: "mcp_read admin")
    end

    assert_response :bad_request
    assert_equal "invalid_scope", response.parsed_body["error"]
    assert_includes response.headers["Cache-Control"], "no-store"
  end

  test "device authorization rejects an unknown client" do
    post "/oauth/authorize_device", params: { client_id: "missing", scope: "mcp_read" }

    assert_response :unauthorized
    assert_equal "invalid_client", response.parsed_body["error"]
  end

  test "device authorization is rate limited per IP" do
    Oauth::DeviceAuthorizationRequestsController::INITIATION_LIMIT.times do
      initiate_device_authorization(scope: "mcp_read")
      assert_response :success
    end

    initiate_device_authorization(scope: "mcp_read")

    assert_response :too_many_requests
    assert_equal "temporarily_unavailable", response.parsed_body["error"]
    assert_equal Oauth::DeviceAuthorizationRequestsController::INITIATION_WINDOW.to_i.to_s, response.headers["Retry-After"]
    assert_equal "no-store", response.headers["Cache-Control"]
  end

  test "device authorization fails closed when the rate-limit counter is unavailable" do
    assert_no_difference "OauthDeviceGrant.count" do
      with_unavailable_device_rate_limit_store do
        initiate_device_authorization(scope: "mcp_read")
      end
    end

    assert_response :service_unavailable
    assert_equal "temporarily_unavailable", response.parsed_body["error"]
    assert_equal Oauth::DeviceAuthorizationRequestsController::RATE_LIMITER_RETRY_AFTER.to_s,
      response.headers["Retry-After"]
    assert_equal "no-store", response.headers["Cache-Control"]
    assert_equal "no-cache", response.headers["Pragma"]
  end

  test "device authorization rejects confidential clients" do
    confidential_application = create_oauth_application(name: "Server-side client", confidential: true)

    assert_no_difference "OauthDeviceGrant.count" do
      post "/oauth/authorize_device", params: {
        client_id: confidential_application.uid,
        client_secret: confidential_application.plaintext_secret,
        scope: "mcp_read"
      }
    end

    assert_response :unauthorized
    assert_equal "invalid_client", response.parsed_body["error"]
  end

  test "polling reports pending and slow down" do
    codes = initiate_device_authorization

    poll_for_token(codes["device_code"])
    assert_response :bad_request
    assert_equal "authorization_pending", response.parsed_body["error"]

    poll_for_token(codes["device_code"])
    assert_response :bad_request
    assert_equal "slow_down", response.parsed_body["error"]
    assert_equal 10, grant_for(codes).reload.polling_interval
  end

  test "approval issues a refreshable user-scoped token once" do
    codes = initiate_device_authorization
    sign_in(@user)

    get "/oauth/device", params: { user_code: codes["user_code"] }
    assert_response :success
    assert_select "[data-testid='device-client-name']", text: "Screenote CLI"
    assert_select "[data-testid='device-user-code']", text: codes["user_code"]
    assert_select "[data-testid='device-scope-mcp-read']", text: /project members, invitations, and their email addresses/i
    assert_select "[data-testid='device-scope-mcp-write']", text: /including removing members/i
    assert_select "select[data-testid='device-principal-select']" do
      assert_select "option[value='']", text: /all current projects/i
      assert_select "option[value='#{@project.id}']", text: @project.name
      assert_select "option[value='#{@foreign_project.id}']", count: 0
    end

    post "/oauth/device", params: { user_code: codes["user_code"], decision: "approve" }
    assert_response :success
    assert_select "[data-testid='device-authorization-approved']"

    approved_grant = grant_for(codes).reload
    assert_equal @user.id, approved_grant.resource_owner_id
    assert_equal "user", approved_grant.principal_kind
    assert_nil approved_grant.project_id

    poll_for_token(codes["device_code"])
    assert_response :success
    token_response = response.parsed_body
    assert token_response["access_token"].present?
    assert token_response["refresh_token"].present?

    token = Doorkeeper::AccessToken.by_token(token_response["access_token"])
    assert_equal @user.id, token.resource_owner_id
    assert_equal "user", token.principal_kind
    assert_nil token.project_id
    assert_equal "mcp_read mcp_write", token.scopes.to_s

    get api_v1_projects_path, headers: { "Authorization" => "Bearer #{token_response['access_token']}" }
    assert_response :success
    assert_equal @user.project_ids.sort, response.parsed_body["projects"].pluck("id").sort

    post "/oauth/token", params: {
      grant_type: "refresh_token",
      refresh_token: token_response["refresh_token"],
      client_id: @application.uid
    }
    assert_response :success
    refreshed_token = Doorkeeper::AccessToken.by_token(response.parsed_body.fetch("access_token"))
    assert_equal @user.id, refreshed_token.resource_owner_id
    assert_equal "user", refreshed_token.principal_kind
    assert_nil refreshed_token.project_id

    poll_for_token(codes["device_code"])
    assert_response :bad_request
    assert_equal "invalid_grant", response.parsed_body["error"]
  end

  test "project approval binds device exchange and refresh rotation to that project" do
    codes = initiate_device_authorization
    sign_in(@user)

    get "/oauth/device", params: { user_code: codes["user_code"] }
    assert_response :success

    post "/oauth/device", params: {
      user_code: codes["user_code"],
      decision: "approve",
      principal_project_id: @project.id
    }
    assert_response :success

    approved_grant = grant_for(codes).reload
    assert_equal @user.id, approved_grant.resource_owner_id
    assert_equal "project", approved_grant.principal_kind
    assert_equal @project.id, approved_grant.project_id

    poll_for_token(codes["device_code"])
    assert_response :success
    token_response = response.parsed_body
    token = Doorkeeper::AccessToken.by_token(token_response.fetch("access_token"))
    assert_equal @user.id, token.resource_owner_id
    assert_equal "project", token.principal_kind
    assert_equal @project.id, token.project_id

    post "/oauth/token", params: {
      grant_type: "refresh_token",
      refresh_token: token_response.fetch("refresh_token"),
      client_id: @application.uid
    }
    assert_response :success

    refreshed_token = Doorkeeper::AccessToken.by_token(response.parsed_body.fetch("access_token"))
    assert_equal @user.id, refreshed_token.resource_owner_id
    assert_equal "project", refreshed_token.principal_kind
    assert_equal @project.id, refreshed_token.project_id
  end

  test "foreign project approval is rejected without authorizing or minting a token" do
    codes = initiate_device_authorization
    sign_in(@user)

    assert_no_difference "Doorkeeper::AccessToken.count" do
      post "/oauth/device", params: {
        user_code: codes["user_code"],
        decision: "approve",
        principal_project_id: @foreign_project.id
      }
    end

    assert_response :unprocessable_entity
    assert_select "[data-testid='device-principal-error']", text: /currently belong to/i
    grant = grant_for(codes).reload
    assert_nil grant.resource_owner_id
    assert_nil grant.approved_at
    assert_nil grant.principal_kind
    assert_nil grant.project_id
  end

  test "project approval is rejected when membership becomes stale before submission" do
    project = @foreign_project
    membership = project.project_memberships.create!(user: @user, role: :member)
    codes = initiate_device_authorization
    sign_in(@user)

    get "/oauth/device", params: { user_code: codes["user_code"] }
    assert_response :success
    assert_select "option[value='#{project.id}']", text: project.name
    membership.destroy!

    assert_no_difference "Doorkeeper::AccessToken.count" do
      post "/oauth/device", params: {
        user_code: codes["user_code"],
        decision: "approve",
        principal_project_id: project.id
      }
    end

    assert_response :unprocessable_entity
    assert_select "[data-testid='device-principal-error']", text: /currently belong to/i
    grant = grant_for(codes).reload
    assert_nil grant.resource_owner_id
    assert_nil grant.approved_at
    assert_nil grant.principal_kind
    assert_nil grant.project_id
  end

  test "an approved project device grant cannot mint a token after membership becomes stale" do
    project = @foreign_project
    membership = project.project_memberships.create!(user: @user, role: :member)
    codes = initiate_device_authorization
    sign_in(@user)

    post "/oauth/device", params: {
      user_code: codes["user_code"],
      decision: "approve",
      principal_project_id: project.id
    }
    assert_response :success
    grant_id = grant_for(codes).id
    membership.destroy!

    assert_no_difference "Doorkeeper::AccessToken.count" do
      poll_for_token(codes["device_code"])
    end

    assert_response :bad_request
    assert_equal "invalid_grant", response.parsed_body["error"]
    assert_not OauthDeviceGrant.exists?(grant_id)
  end

  test "a device verification query cannot preselect a project" do
    codes = initiate_device_authorization
    sign_in(@user)

    assert_no_difference "Doorkeeper::AccessToken.count" do
      get "/oauth/device", params: {
        user_code: codes["user_code"],
        principal_project_id: @project.id
      }
    end

    assert_response :success
    assert_select "option[value='#{@project.id}'][selected]", count: 0
    grant = grant_for(codes).reload
    assert_nil grant.resource_owner_id
    assert_nil grant.principal_kind
    assert_nil grant.project_id
  end

  test "device initiation ignores client supplied principal attributes" do
    post "/oauth/authorize_device", params: {
      client_id: @application.uid,
      scope: "mcp_read",
      principal_kind: "project",
      project_id: @project.id
    }

    assert_response :success
    grant = grant_for(response.parsed_body)
    assert_nil grant.resource_owner_id
    assert_nil grant.principal_kind
    assert_nil grant.project_id
  end

  test "deleting a selected project consumes its pending approved device credential" do
    project = @user.owned_projects.create!(name: "Disposable device project")
    codes = initiate_device_authorization
    sign_in(@user)

    post "/oauth/device", params: {
      user_code: codes["user_code"],
      decision: "approve",
      principal_project_id: project.id
    }
    assert_response :success
    grant_id = grant_for(codes).id

    project.destroy!

    assert_not OauthDeviceGrant.exists?(grant_id)
    assert_no_difference "Doorkeeper::AccessToken.count" do
      poll_for_token(codes["device_code"])
    end
    assert_response :bad_request
    assert_equal "invalid_grant", response.parsed_body["error"]
  end

  test "denial returns normative access denied and consumes the grant" do
    codes = initiate_device_authorization
    sign_in(@user)

    post "/oauth/device", params: { user_code: codes["user_code"], decision: "deny" }
    assert_response :success
    assert_select "[data-testid='device-authorization-denied']"

    poll_for_token(codes["device_code"])
    assert_response :bad_request
    assert_equal "access_denied", response.parsed_body["error"]

    poll_for_token(codes["device_code"])
    assert_response :bad_request
    assert_equal "invalid_grant", response.parsed_body["error"]
  end

  test "expired device code returns expired token" do
    codes = initiate_device_authorization
    grant_for(codes).update_column(:expires_at, 1.second.ago)

    poll_for_token(codes["device_code"])

    assert_response :bad_request
    assert_equal "expired_token", response.parsed_body["error"]
  end

  test "a different client cannot exchange the device code" do
    codes = initiate_device_authorization
    other_application = create_oauth_application(name: "Other client")

    poll_for_token(codes["device_code"], client_id: other_application.uid)

    assert_response :bad_request
    assert_equal "invalid_grant", response.parsed_body["error"]
    assert grant_for(codes).present?
  end

  private

  def initiate_device_authorization(scope: "mcp_read mcp_write")
    post "/oauth/authorize_device", params: { client_id: @application.uid, scope: scope }
    response.parsed_body
  end

  def poll_for_token(device_code, client_id: @application.uid)
    post "/oauth/token", params: {
      grant_type: DEVICE_GRANT_TYPE,
      device_code: device_code,
      client_id: client_id
    }
  end

  def grant_for(codes)
    OauthDeviceGrant.find_by_plaintext_device_code(codes["device_code"])
  end
end
