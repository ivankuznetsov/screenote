# frozen_string_literal: true

require "test_helper"

class OmniauthSecurityTest < ActionDispatch::IntegrationTest
  test "request phase uses POST and OmniAuth authenticity token protection" do
    validator = OmniAuth.config.request_validation_phase

    assert_equal %i[post], OmniAuth.config.allowed_request_methods
    assert_instance_of OmniAuth::AuthenticityTokenProtection, validator
    assert_equal :_csrf_token, validator.options.fetch(:key)
  end

  test "Rails form tokens reach the provider while missing and invalid tokens are rejected" do
    previous_forgery_protection = ActionController::Base.allow_forgery_protection
    previous_test_mode = OmniAuth.config.test_mode
    ActionController::Base.allow_forgery_protection = true
    OmniAuth.config.test_mode = false

    get new_session_path
    token = css_select(
      "form[action='/auth/google_oauth2'] input[name='authenticity_token']"
    ).first&.[]("value")
    origin = css_select(
      "form[action='/auth/google_oauth2'] input[name='origin']"
    ).first&.[]("value")

    assert_predicate token, :present?
    assert_equal new_session_path, origin

    post "/auth/google_oauth2", params: { authenticity_token: token, origin: origin }

    assert_response :redirect
    assert_equal "accounts.google.com", URI.parse(response.location).host

    [ nil, "invalid-token" ].each do |invalid_token|
      params = { origin: new_session_path }
      params[:authenticity_token] = invalid_token if invalid_token
      post "/auth/google_oauth2", params: params

      assert_response :redirect
      assert_includes response.location, "/auth/failure"
      assert_includes response.location, "message=authenticity_error"
    end
  ensure
    ActionController::Base.allow_forgery_protection = previous_forgery_protection
    OmniAuth.config.test_mode = previous_test_mode
  end

  test "configured OAuth2 strategies keep callback state verification enabled" do
    builder = Rails.application.config.middleware.find { |middleware| middleware.klass == OmniAuth::Builder }

    assert builder, "expected enabled SaaS providers to install OmniAuth middleware"
    assert_not OmniAuth::Strategies::GoogleOauth2.default_options.provider_ignores_state
    assert_not OmniAuth::Strategies::GitHub.default_options.provider_ignores_state
  end

  test "OAuth uses the canonical origin rather than request forwarding headers" do
    assert_equal Screenote::Deployment.current.base_url, OmniAuth.config.full_host

    post "/auth/google_oauth2",
      headers: {
        "Host" => "www.example.com",
        "Origin" => "https://evil.example.test",
        "X-Forwarded-Host" => "evil.example.test:9443",
        "X-Forwarded-Proto" => "https"
      }

    assert_response :redirect
    assert_includes response.location, "/auth/failure"
    assert_not_includes response.location, "evil.example.test"
  end

  test "mismatched OAuth callback state creates no account or session" do
    assert_no_difference([ "User.count", "Session.count" ]) do
      get "/auth/google_oauth2/callback",
        params: { code: "untrusted-code", state: "mismatched-state" }
    end

    assert_response :redirect
    assert_includes response.location, "/auth/failure"
  end
end
