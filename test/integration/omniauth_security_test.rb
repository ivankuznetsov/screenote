# frozen_string_literal: true

require "test_helper"

class OmniauthSecurityTest < ActionDispatch::IntegrationTest
  test "request phase uses POST and OmniAuth authenticity token protection" do
    assert_equal %i[post], OmniAuth.config.allowed_request_methods
    assert_equal OmniAuth::AuthenticityTokenProtection, OmniAuth.config.request_validation_phase
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
