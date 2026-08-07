# frozen_string_literal: true

require "test_helper"

class Oauth::DeviceAuthorizationRateLimiterTest < ActiveSupport::TestCase
  test "backend exceptions fail closed with a stable unavailable error" do
    failing_store = Object.new
    failing_store.define_singleton_method(:increment) { |*, **| raise "cache password=private" }

    error = assert_raises(Oauth::DeviceAuthorizationRateLimiter::Unavailable) do
      Oauth::DeviceAuthorizationRateLimiter.exceeded?(
        bucket: :initiation,
        identity: "203.0.113.10",
        limit: 20,
        within: 1.minute,
        rate_store: failing_store
      )
    end

    assert_equal "rate-limit counter unavailable", error.message
  end
end
