# frozen_string_literal: true

# screenote-edition: self_hosted

require "test_helper"

class RateLimitFailClosedTest < ActiveSupport::TestCase
  ENDPOINT_CONTRACTS = {
    bootstrap: [ "app/controllers/bootstrap_controller.rb", /RateLimitStore::Unavailable/ ],
    login: [ "app/controllers/sessions_controller.rb", /rate_limit\s+to:/ ],
    recovery: [ "app/controllers/account_recoveries_controller.rb", /RateLimitStore::Unavailable/ ],
    registration: [ "app/controllers/registrations_controller.rb", /rate_limit\s+to:/ ],
    dynamic_registration: [
      "app/controllers/oauth/registrations_controller.rb",
      /DynamicClientRegistrationRateLimiter::Unavailable/
    ],
    device_request: [
      "app/controllers/oauth/device_authorization_requests_controller.rb",
      /DeviceAuthorizationRateLimiter::Unavailable/
    ],
    device_verification: [
      "app/controllers/oauth/device_authorizations_controller.rb",
      /DeviceAuthorizationRateLimiter::Unavailable/
    ],
    upload: [ "app/controllers/api/v1/screenshot_images_controller.rb", /RateLimitStore::Unavailable/ ],
    mcp: [ "config/initializers/fast_mcp.rb", /RateLimitStore::Unavailable/ ]
  }.freeze

  test "production controller throttles use the fail-closed cache wrapper" do
    source = Rails.root.join("config/environments/production.rb").read

    assert_match(
      /config\.action_controller\.cache_store\s*=\s*Screenote::RateLimitStore\.new/,
      source
    )
  end

  test "every abuse-sensitive endpoint declares its fail-closed limiter contract" do
    ENDPOINT_CONTRACTS.each do |endpoint, (path, pattern)|
      source = Rails.root.join(path).read
      assert_match pattern, source, "#{endpoint} lost its rate-limit failure boundary in #{path}"
    end
  end

  test "backend exceptions and ambiguous nil increments are unavailable" do
    [ IOError.new("offline"), nil ].each do |outcome|
      backend = Object.new
      backend.define_singleton_method(:increment) do |*, **|
        raise outcome if outcome.is_a?(Exception)

        outcome
      end
      store = Screenote::RateLimitStore.new(store: -> { backend })

      assert_raises(Screenote::RateLimitStore::Unavailable) do
        store.increment("u8-rate-limit-probe", expires_in: 1.minute)
      end
    end
  end

  test "unhandled limiter outages become retryable non-cacheable HTTP responses" do
    app = ->(_environment) { raise Screenote::RateLimitStore::Unavailable, "offline" }
    response = Screenote::RateLimitFailureMiddleware.new(app).call({})
    status, headers, body = response

    assert_equal 503, status
    assert_equal "60", headers.fetch("Retry-After")
    assert_equal "no-store", headers.fetch("Cache-Control")
    assert_match(/temporarily unavailable/i, body.join)
  end
end
