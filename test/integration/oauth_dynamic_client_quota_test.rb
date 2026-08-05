# frozen_string_literal: true

require "test_helper"

class OauthDynamicClientQuotaTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:alice)
    @project = projects(:alice_project)
    @existing_application = dynamic_application("Existing authorized client", 49_001)
    @new_application = dynamic_application("New authorization client", 49_002)
    create_refresh_credential(application: @existing_application)
    Rails.cache.clear
    Oauth::DeviceAuthorizationRateLimiter.reset!
    sign_in(@user)
  end

  teardown do
    Rails.cache.clear
    Oauth::DeviceAuthorizationRateLimiter.reset!
  end

  test "authorization code consent rejects a new client at quota and permits reauthorization" do
    _verifier, challenge = generate_pkce_challenge

    with_maximum_authorized_clients(1) do
      assert_no_difference "Doorkeeper::AccessGrant.count" do
        post "/oauth/authorize", params: authorization_params(@new_application, challenge)
      end
      assert_response :unprocessable_entity
      assert_select "[data-testid='oauth-principal-error']", text: /active dynamic clients/i

      assert_difference "Doorkeeper::AccessGrant.count", 1 do
        post "/oauth/authorize", params: authorization_params(@existing_application, challenge)
      end
      assert_response :redirect
    end
  end

  test "device approval rejects a new client at quota and leaves its grant pending" do
    post "/oauth/authorize_device", params: {
      client_id: @new_application.uid,
      scope: "mcp_read"
    }
    assert_response :success
    codes = response.parsed_body

    with_maximum_authorized_clients(1) do
      post "/oauth/device", params: {
        user_code: codes.fetch("user_code"),
        decision: "approve"
      }
    end

    assert_response :unprocessable_entity
    assert_select "[data-testid='device-principal-error']", text: /active dynamic clients/i
    grant = OauthDeviceGrant.find_by_plaintext_device_code(codes.fetch("device_code"))
    assert_nil grant.resource_owner_id
    assert_nil grant.approved_at
    assert_nil grant.principal_kind
  end

  test "dynamic project consent and device approval succeed within remaining capacity" do
    _verifier, challenge = generate_pkce_challenge

    with_maximum_authorized_clients(2) do
      post "/oauth/authorize", params: authorization_params(@new_application, challenge).merge(
        principal_project_id: @project.id
      )
      assert_response :redirect
      code = Rack::Utils.parse_query(URI.parse(response.location).query).fetch("code")
      authorization_grant = Doorkeeper::AccessGrant.by_token(code)
      assert_equal "project", authorization_grant.principal_kind
      assert_equal @project.id, authorization_grant.project_id

      post "/oauth/authorize_device", params: {
        client_id: @new_application.uid,
        scope: "mcp_read"
      }
      assert_response :success
      codes = response.parsed_body

      post "/oauth/device", params: {
        user_code: codes.fetch("user_code"),
        decision: "approve",
        principal_project_id: @project.id
      }
      assert_response :success
      device_grant = OauthDeviceGrant.find_by_plaintext_device_code(codes.fetch("device_code"))
      assert_equal "project", device_grant.principal_kind
      assert_equal @project.id, device_grant.project_id
    end
  end

  private

  def dynamic_application(name, port)
    create_oauth_application(
      name:,
      redirect_uri: "http://127.0.0.1:#{port}/callback"
    ).tap do |application|
      application.update!(dynamic: true, scopes: "mcp_read mcp_write")
    end
  end

  def create_refresh_credential(application:)
    Doorkeeper::AccessToken.create!(
      application:,
      resource_owner_id: @user.id,
      principal_kind: "user",
      scopes: "mcp_read",
      expires_in: 1.hour,
      refresh_token: Digest::SHA256.hexdigest(SecureRandom.urlsafe_base64(32))
    )
  end

  def authorization_params(application, challenge)
    {
      client_id: application.uid,
      redirect_uri: application.redirect_uri,
      response_type: "code",
      scope: "mcp_read",
      code_challenge: challenge,
      code_challenge_method: "S256",
      state: "quota-state"
    }
  end

  def with_maximum_authorized_clients(limit)
    singleton_class = Oauth::DynamicClientAuthorizationQuota.singleton_class
    original = Oauth::DynamicClientAuthorizationQuota.method(:maximum_authorized_clients_per_user)
    singleton_class.define_method(:maximum_authorized_clients_per_user) { limit }
    singleton_class.send(:private, :maximum_authorized_clients_per_user)
    yield
  ensure
    singleton_class&.define_method(:maximum_authorized_clients_per_user, original)
    singleton_class&.send(:private, :maximum_authorized_clients_per_user)
  end
end
