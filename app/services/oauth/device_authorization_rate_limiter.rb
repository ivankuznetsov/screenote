# frozen_string_literal: true

module Oauth
  class DeviceAuthorizationRateLimiter
    # The shared store's error, so the OAuth controllers' rescues and the
    # fail-closed middleware match the same class.
    Unavailable = Screenote::RateLimitStore::Unavailable

    class << self
      def exceeded?(bucket:, identity:, limit:, within:, rate_store: store)
        counter = Screenote::RateLimitStore.new(store: -> { rate_store })
        counter.increment(cache_key(bucket, identity), 1, expires_in: within) > limit
      end

      def reset!
        test_store&.clear
      end

      private

      def cache_key(bucket, identity)
        identity_digest = Digest::SHA256.hexdigest(identity.to_s)
        "oauth-device-rate-limit:#{bucket}:#{identity_digest}"
      end

      def store
        test_store || Rails.cache
      end

      def test_store
        return unless Rails.env.test?

        @test_store ||= ActiveSupport::Cache::MemoryStore.new
      end
    end
  end
end
