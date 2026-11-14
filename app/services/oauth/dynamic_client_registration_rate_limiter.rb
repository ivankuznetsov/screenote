# frozen_string_literal: true

module Oauth
  class DynamicClientRegistrationRateLimiter
    LIMIT = 10
    WINDOW = 1.hour

    # The shared store's error, so the registration controller's rescue and
    # the fail-closed middleware match the same class.
    Unavailable = Screenote::RateLimitStore::Unavailable

    class << self
      def exceeded?(identity:, rate_store: store)
        digest = Digest::SHA256.hexdigest(identity.to_s)
        counter = Screenote::RateLimitStore.new(store: -> { rate_store })
        counter.increment("oauth-dcr-rate-limit:#{digest}", 1, expires_in: WINDOW) > LIMIT
      end

      def reset!
        test_store&.clear
      end

      private

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
