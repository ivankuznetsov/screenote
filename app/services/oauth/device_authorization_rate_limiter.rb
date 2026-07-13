# frozen_string_literal: true

module Oauth
  class DeviceAuthorizationRateLimiter
    class Unavailable < StandardError; end

    class << self
      def exceeded?(bucket:, identity:, limit:, within:)
        count = store.increment(cache_key(bucket, identity), 1, expires_in: within)
        raise Unavailable, "rate-limit counter unavailable" if count.nil?

        count > limit
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
