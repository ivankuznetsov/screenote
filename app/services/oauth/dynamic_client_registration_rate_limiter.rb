# frozen_string_literal: true

module Oauth
  class DynamicClientRegistrationRateLimiter
    LIMIT = 10
    WINDOW = 1.hour

    class Unavailable < StandardError; end

    class << self
      def exceeded?(identity:, rate_store: store)
        digest = Digest::SHA256.hexdigest(identity.to_s)
        count = rate_store.increment("oauth-dcr-rate-limit:#{digest}", 1, expires_in: WINDOW)
        raise Unavailable, "rate-limit counter unavailable" if count.nil?

        count > LIMIT
      rescue Unavailable
        raise
      rescue StandardError
        raise Unavailable, "rate-limit counter unavailable"
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
