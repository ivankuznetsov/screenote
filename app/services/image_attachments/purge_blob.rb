# frozen_string_literal: true

module ImageAttachments
  # Deletes stored bytes before the row that names them.
  #
  # `ActiveStorage::Blob#purge` destroys the tracking row first and only then
  # asks the service to delete. A provider failure at that point has already
  # thrown away the one durable record of the key, so nothing — not cleanup, not
  # reconciliation, not an operator — can ever retry it. Deleting first inverts
  # that: a failed delete leaves the row behind as an unattached blob the
  # bounded reconciliation pass finds again on its next run.
  module PurgeBlob
    class << self
      def call(blob)
        return false unless blob

        blob.delete
        blob.destroy
        true
      rescue StandardError => error
        Screenote::Monitoring.notify(
          error,
          context: { active_storage_blob_id: blob.id, active_storage_blob_key: blob.key }
        )
        false
      end
    end
  end
end
