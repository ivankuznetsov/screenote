# frozen_string_literal: true

require "test_helper"

class SessionSecurityTest < ActionDispatch::IntegrationTest
  test "HTTP canonical origin creates a non-secure session cookie" do
    with_deployment("http://screenote.internal") do
      post session_path, params: { email: users(:alice).email, password: "password123" }

      assert_response :redirect
      cookie = Array(response.headers.fetch("Set-Cookie")).join("\n")
      assert_match(/session_token=/, cookie)
      assert_no_match(/; secure/i, cookie)
    end
  end

  test "HTTPS canonical origin creates a secure session cookie" do
    with_deployment("https://screenote.example.test") do
      https!
      post session_path, params: { email: users(:alice).email, password: "password123" }

      assert_response :redirect
      cookie = Array(response.headers.fetch("Set-Cookie")).join("\n")
      assert_match(/session_token=/, cookie)
      assert_match(/; secure/i, cookie)
    end
  end

  private

  def with_deployment(base_url)
    deployment = Screenote::Deployment.new(
      {
        "SCREENOTE_EDITION" => "self_hosted",
        "SCREENOTE_BASE_URL" => base_url,
        "SECRET_KEY_BASE" => "a" * 64,
        "SCREENOTE_BOOTSTRAP_TOKEN" => "b" * 43
      },
      production: true
    )
    previous = Screenote::Deployment.current
    Screenote::Deployment.instance_variable_set(:@current, deployment)
    yield
  ensure
    Screenote::Deployment.instance_variable_set(:@current, previous) if previous
  end
end
