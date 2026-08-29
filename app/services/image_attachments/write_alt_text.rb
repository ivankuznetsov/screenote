# frozen_string_literal: true

module ImageAttachments
  # Writes a draft description under the global lock order — the batch first,
  # then the attachment row. Taking the batch lock is what makes a description
  # racing a claim resolve as a plain not-found: once the claim has moved the
  # row onto its message the row is no longer part of the batch, so the write
  # can never land on submitted metadata or trip its immutability guard.
  class WriteAltText
    class << self
      def call(batch:, attachment_id:, alt_text:)
        new(batch: batch, attachment_id: attachment_id, alt_text: alt_text).call
      end
    end

    def initialize(batch:, attachment_id:, alt_text:)
      @batch = batch
      @attachment_id = attachment_id
      @alt_text = alt_text
    end

    def call
      attachment = nil

      ImageAttachment.transaction do
        batch.lock!
        attachment = batch.image_attachments.lock.find_by(id: attachment_id)
        # A removal tombstone is a row the composer has already discarded, and
        # removal nulls its metadata. Answering not-found keeps the description
        # write on the same removal contract every other draft call follows.
        raise ActiveRecord::RecordNotFound if attachment.nil? || attachment.removal_tombstone?

        attachment.update!(alt_text: alt_text)
      end

      batch.touch_activity! if batch.usable?
      attachment
    rescue ActiveRecord::RecordInvalid
      # Over-length descriptions are ordinary client input, so they answer with
      # the same machine code envelope as every other draft failure rather than
      # escaping as a 500.
      raise Error.new(code: "alt_text_too_long")
    end

    private

    attr_reader :batch, :attachment_id, :alt_text
  end
end
