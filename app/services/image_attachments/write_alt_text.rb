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
        raise ActiveRecord::RecordNotFound unless attachment

        attachment.update!(alt_text: alt_text)
      end

      batch.touch_activity! if batch.usable?
      attachment
    end

    private

    attr_reader :batch, :attachment_id, :alt_text
  end
end
