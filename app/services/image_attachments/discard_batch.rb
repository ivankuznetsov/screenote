# frozen_string_literal: true

module ImageAttachments
  # Throws away an unclaimed draft batch and its attachments. Only an explicit
  # composer cancel calls this: ordinary disconnect and navigation still leave a
  # batch for its 24 hour recovery window.
  #
  # Uses the global lock order — the batch first, then its attachment rows —
  # and rechecks the state inside the lock, so a cancel that races a successful
  # claim resolves as "already claimed" and can never take attachments away
  # from a posted message. Discarding twice is not an error.
  class DiscardBatch
    Result = Data.define(:discarded) do
      def discarded?
        discarded
      end
    end

    class << self
      def call(batch:)
        new(batch: batch).call
      end
    end

    def initialize(batch:)
      @batch = batch
    end

    def call
      discarded = ImageAttachmentBatch.transaction do
        batch.lock!
        next false unless batch.state_open?

        # destroy cascades to the attachment rows, whose Active Storage
        # lifecycle purges the primary blob together with every derivative.
        batch.image_attachments.ordered.lock.to_a
        batch.destroy!
        true
      end

      Result.new(discarded: discarded)
    rescue ActiveRecord::RecordNotFound
      # Another cancel already reclaimed it.
      Result.new(discarded: false)
    end

    private

    attr_reader :batch
  end
end
