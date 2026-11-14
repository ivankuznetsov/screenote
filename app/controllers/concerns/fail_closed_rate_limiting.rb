# frozen_string_literal: true

# When the rate-limit store is unreachable, refuse the request with a
# retryable, non-cacheable 503 instead of serving it unthrottled.
module FailClosedRateLimiting
  extend ActiveSupport::Concern

  RATE_LIMITER_RETRY_AFTER = 60

  included do
    rescue_from Screenote::RateLimitStore::Unavailable, with: :render_rate_limiter_unavailable
  end

  private

  def render_rate_limiter_unavailable(_error)
    response.set_header("Retry-After", RATE_LIMITER_RETRY_AFTER.to_s)
    response.set_header("Cache-Control", "no-store")
    response.set_header("Pragma", "no-cache")
    head :service_unavailable
  end
end
