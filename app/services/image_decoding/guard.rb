# frozen_string_literal: true

require "concurrent"

module ImageDecoding
  class Guard
    WAIT_SECONDS = 5
    MAX_CONCURRENCY = 2
    CONCURRENCY = Integer(ENV.fetch("SCREENOTE_IMAGE_DECODER_CONCURRENCY", "2"), 10).tap do |value|
      unless (1..MAX_CONCURRENCY).cover?(value)
        raise ArgumentError,
          "SCREENOTE_IMAGE_DECODER_CONCURRENCY must be between 1 and #{MAX_CONCURRENCY}"
      end
    end
    SEMAPHORE = Concurrent::Semaphore.new(CONCURRENCY)

    class Busy < StandardError; end

    class << self
      def synchronize(timeout: WAIT_SECONDS)
        acquired = SEMAPHORE.try_acquire(1, timeout)
        raise Busy, "image decoder is busy" unless acquired

        yield
      ensure
        SEMAPHORE.release if acquired
      end
    end
  end
end
