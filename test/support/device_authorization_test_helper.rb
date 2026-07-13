# frozen_string_literal: true

module DeviceAuthorizationTestHelper
  def with_unavailable_device_rate_limit_store
    store = Oauth::DeviceAuthorizationRateLimiter.send(:store)
    original_increment = store.method(:increment)
    store.define_singleton_method(:increment) { |*, **| nil }

    yield
  ensure
    store&.define_singleton_method(:increment, original_increment) if original_increment
  end
end
