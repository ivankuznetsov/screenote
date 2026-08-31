# frozen_string_literal: true

module ImageAttachments
  # Idempotent draft removal. A tiny client-key tombstone remains in the batch
  # until claim/discard/expiry, so removal also wins when it reaches the server
  # before an in-flight upload has reserved its row. The tombstone is omitted
  # from resume/claim and prevents that client key from being uploaded again.
  class RemoveAttachment
    Result = Data.define(:removed)

    class << self
      def call(batch:, attachment_id: nil, client_key: nil)
        new(batch: batch, attachment_id: attachment_id, client_key: client_key).call
      end
    end

    def initialize(batch:, attachment_id: nil, client_key: nil)
      @batch = batch
      @attachment_id = attachment_id
      @client_key = client_key.to_s.presence
    end

    def call
      attachment = nil

      ImageAttachment.transaction do
        batch.lock!
        next unless batch.state_open?

        attachment = find_or_reserve_tombstone
        next unless attachment

        attachment.update!(
          state: :failed,
          failure_code: ImageAttachment::REMOVAL_TOMBSTONE
        ) unless attachment.removal_tombstone?
      end

      purge_removed_image(attachment)
      batch.touch_activity! if batch.usable?
      Result.new(removed: attachment.present?)
    end

    private

    attr_reader :batch, :attachment_id, :client_key

    def find_or_reserve_tombstone
      attachment = if attachment_id.present?
        batch.image_attachments.ordered.lock.find_by(id: attachment_id)
      elsif client_key.present?
        batch.image_attachments.ordered.lock.find_by(client_key: client_key)
      end
      return attachment if attachment
      return unless client_key

      validate_client_key!
      created = batch.image_attachments.create!(
        user_id: batch.user_id,
        project_id: batch.project_id,
        client_key: client_key,
        state: :failed,
        failure_code: ImageAttachment::REMOVAL_TOMBSTONE
      )
      prune_tombstones!(created)
      created
    end

    # A tombstone exists to beat an upload that is already in flight for the
    # same client key, so only the recent ones can still do any work. Without a
    # bound, a client that invents a new key per DELETE could park unbounded
    # rows on one open batch and make every later claim, removal, and cleanup
    # pass lock more of them. The window is kept to the number of files a
    # message may carry, and the oldest markers — the ones no live upload can
    # still be racing — are dropped to make room.
    def prune_tombstones!(created)
      tombstones = batch.image_attachments
        .where(failure_code: ImageAttachment::REMOVAL_TOMBSTONE)
        .order(:id)
        .lock
        .to_a
      surplus = tombstones.size - ImageAttachment::MAX_FILES
      return unless surplus.positive?

      tombstones.first(surplus).each { |marker| marker.destroy! unless marker.id == created.id }
    end

    # The marker is committed before storage is touched, so a failed purge can
    # never let the upload come back. Keeping byte_size until purge succeeds
    # also keeps the account cap fail-closed during a storage outage.
    def purge_removed_image(attachment)
      return unless attachment&.persisted?

      if attachment.image.attached?
        # Detach first, then delete the bytes before the row that names them:
        # a provider failure leaves a discoverable unattached blob rather than
        # an untracked key.
        blob = attachment.image.blob
        attachment.image.detach
        PurgeBlob.call(blob)
      end

      ImageAttachment.transaction do
        batch.lock!
        marker = batch.image_attachments.find_by(id: attachment.id)
        next unless marker&.removal_tombstone?

        marker.update!(
          alt_text: nil,
          media_type: nil,
          width: nil,
          height: nil,
          byte_size: nil
        )
      end
    end

    def validate_client_key!
      raise Error.new(code: "missing_client_key") if client_key.blank?
      raise Error.new(code: "invalid_client_key") if client_key.length > 64
    end
  end
end
