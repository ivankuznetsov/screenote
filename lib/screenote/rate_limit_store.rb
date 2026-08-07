# frozen_string_literal: true

module Screenote
  class RateLimitStore
    class Unavailable < StandardError; end

    def initialize(store: -> { Rails.cache })
      @store = store
    end

    def increment(key, amount = 1, **options)
      count = @store.call.increment(key, amount, **options)
      raise Unavailable, "rate-limit backend unavailable" if count.nil?

      count
    rescue Unavailable
      raise
    rescue StandardError
      raise Unavailable, "rate-limit backend unavailable"
    end
  end

  class RateLimitFailureMiddleware
    RETRY_AFTER = "60"

    def initialize(app)
      @app = app
    end

    def call(environment)
      @app.call(environment)
    rescue RateLimitStore::Unavailable
      body = "Service temporarily unavailable. Please retry later."
      [
        503,
        {
          "Content-Type" => "text/plain; charset=utf-8",
          "Content-Length" => body.bytesize.to_s,
          "Cache-Control" => "no-store",
          "Retry-After" => RETRY_AFTER
        },
        [ body ]
      ]
    end
  end
end
