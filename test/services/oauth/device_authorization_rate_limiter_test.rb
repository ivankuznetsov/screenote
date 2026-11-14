# frozen_string_literal: true

require "test_helper"

class Oauth::DeviceAuthorizationRateLimiterTest < ActiveSupport::TestCase
  test "backend exceptions fail closed with a stable unavailable error" do
    failing_store = Object.new
    failing_store.define_singleton_method(:increment) { |*, **| raise "cache password=private" }

    error = assert_raises(Oauth::DeviceAuthorizationRateLimiter::Unavailable) do
      exceeded?(rate_store: failing_store)
    end

    assert_equal "rate-limit backend unavailable", error.message
    assert_not_includes error.message, "private"
  end

  test "a missing counter fails closed with the shared store error" do
    absent_store = Object.new
    absent_store.define_singleton_method(:increment) { |*, **| nil }

    assert_raises(Screenote::RateLimitStore::Unavailable) { exceeded?(rate_store: absent_store) }
  end

  test "counts each identity against its limit" do
    store = ActiveSupport::Cache::MemoryStore.new

    assert_not exceeded?(rate_store: store, limit: 1)
    assert exceeded?(rate_store: store, limit: 1)
    assert_not exceeded?(rate_store: store, limit: 1, identity: "198.51.100.7")
  end

  test "both OAuth limiters raise the shared store error class" do
    assert_same Screenote::RateLimitStore::Unavailable, Oauth::DeviceAuthorizationRateLimiter::Unavailable
    assert_same Screenote::RateLimitStore::Unavailable, Oauth::DynamicClientRegistrationRateLimiter::Unavailable
  end

  private

  def exceeded?(rate_store:, limit: 20, identity: "203.0.113.10")
    Oauth::DeviceAuthorizationRateLimiter.exceeded?(
      bucket: :initiation,
      identity: identity,
      limit: limit,
      within: 1.minute,
      rate_store: rate_store
    )
  end
end
