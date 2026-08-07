# frozen_string_literal: true

require "test_helper"

class Screenote::RateLimitStoreTest < ActiveSupport::TestCase
  test "returns the durable counter result" do
    backing_store = ActiveSupport::Cache::MemoryStore.new
    store = Screenote::RateLimitStore.new(store: -> { backing_store })

    assert_equal 1, store.increment("login:user", 1, expires_in: 1.minute)
    assert_equal 2, store.increment("login:user", 1, expires_in: 1.minute)
  end

  test "nil counters fail closed" do
    backing_store = Object.new
    backing_store.define_singleton_method(:increment) { |*, **| nil }
    store = Screenote::RateLimitStore.new(store: -> { backing_store })

    assert_raises(Screenote::RateLimitStore::Unavailable) do
      store.increment("login:user", 1, expires_in: 1.minute)
    end
  end

  test "store errors become a stable unavailable error without leaking details" do
    backing_store = Object.new
    backing_store.define_singleton_method(:increment) { |*, **| raise "redis password=private" }
    store = Screenote::RateLimitStore.new(store: -> { backing_store })

    error = assert_raises(Screenote::RateLimitStore::Unavailable) do
      store.increment("login:user", 1, expires_in: 1.minute)
    end

    assert_equal "rate-limit backend unavailable", error.message
  end

  test "middleware converts unavailable limits into a retryable 503" do
    middleware = Screenote::RateLimitFailureMiddleware.new(
      ->(_environment) { raise Screenote::RateLimitStore::Unavailable, "private cache detail" }
    )

    status, headers, body = middleware.call({})

    assert_equal 503, status
    assert_equal "60", headers.fetch("Retry-After")
    assert_equal "no-store", headers.fetch("Cache-Control")
    assert_not_includes body.join, "private cache detail"
  end
end
