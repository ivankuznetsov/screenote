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
    # Callers that pass a key decode one file at a time within that key before
    # they compete for a global slot. One composer batch retrying while its
    # earlier upload is still decoding must never hold every global slot and
    # answer screenshot work with `decoder_busy`.
    KEYED = {}
    KEYED_MUTEX = Mutex.new

    class Busy < StandardError; end

    class << self
      def synchronize(key: nil, timeout: WAIT_SECONDS, &block)
        return acquire_global(timeout, &block) if key.nil?

        # One deadline spans both stages. Passing the full timeout to each
        # would let a keyed wait and a global wait stack, so a composer could
        # block for twice the budget before it is told the decoder is busy.
        deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + timeout
        acquire_key(key, timeout) { acquire_global(remaining(deadline), &block) }
      end

      private

      def remaining(deadline)
        [ deadline - Process.clock_gettime(Process::CLOCK_MONOTONIC), 0 ].max
      end

      def acquire_global(timeout)
        acquired = SEMAPHORE.try_acquire(1, timeout)
        raise Busy, "image decoder is busy" unless acquired

        yield
      ensure
        SEMAPHORE.release if acquired
      end

      def acquire_key(key, timeout)
        semaphore = checkout(key)
        acquired = semaphore.try_acquire(1, timeout)
        raise Busy, "image decoder is busy" unless acquired

        yield
      ensure
        semaphore.release if acquired
        checkin(key)
      end

      # Entries are reference counted so a long-lived process does not
      # accumulate one semaphore per draft batch it has ever served.
      def checkout(key)
        KEYED_MUTEX.synchronize do
          entry = KEYED[key] ||= { semaphore: Concurrent::Semaphore.new(1), holders: 0 }
          entry[:holders] += 1
          entry[:semaphore]
        end
      end

      def checkin(key)
        KEYED_MUTEX.synchronize do
          entry = KEYED[key]
          next unless entry

          entry[:holders] -= 1
          KEYED.delete(key) if entry[:holders] <= 0
        end
      end
    end
  end
end
