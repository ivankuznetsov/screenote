# frozen_string_literal: true

module ImageAttachments
  # Idempotent draft removal. Uses the global lock order — the batch first,
  # then the attachment row — so a removal racing a claim or a cleanup pass can
  # never leave a message holding a half-purged set.
  class RemoveAttachment
    Result = Data.define(:removed)

    class << self
      def call(batch:, attachment_id:)
        new(batch: batch, attachment_id: attachment_id).call
      end
    end

    def initialize(batch:, attachment_id:)
      @batch = batch
      @attachment_id = attachment_id
    end

    def call
      attachment = nil

      ImageAttachment.transaction do
        batch.lock!
        attachment = batch.image_attachments.ordered.lock.find_by(id: attachment_id)
        next unless attachment

        attachment.destroy!
      end

      batch.touch_activity! if batch.usable?
      Result.new(removed: attachment.present?)
    end

    private

    attr_reader :batch, :attachment_id
  end
end
