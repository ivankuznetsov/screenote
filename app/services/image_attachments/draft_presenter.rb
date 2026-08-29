# frozen_string_literal: true

module ImageAttachments
  # The only attachment shape the browser ever sees. It carries stable IDs,
  # state, immutable metadata, and a protected preview path — never a storage
  # key, a provider URL, or the uploader's original filename.
  class DraftPresenter
    class << self
      def batch(batch)
        {
          batch_id: batch.public_id,
          project_id: batch.project_id,
          state: batch.state,
          expires_at: batch.expires_at.iso8601,
          limits: {
            max_files: ImageAttachment::MAX_FILES,
            max_file_size: ImageAttachment::MAX_FILE_SIZE,
            max_total_size: ImageAttachment::MAX_TOTAL_BYTES,
            accepted_media_types: ImageAttachment::ALLOWED_CONTENT_TYPES
          },
          attachments: batch.image_attachments.active_drafts.ordered.map { |item| attachment(item) }
        }
      end

      def attachment(attachment)
        {
          id: attachment.id,
          client_key: attachment.client_key,
          state: attachment.state,
          alt_text: attachment.alt_text,
          media_type: attachment.media_type,
          width: attachment.width,
          height: attachment.height,
          size: attachment.byte_size,
          preview_url: preview_url(attachment),
          failure: failure(attachment)
        }
      end

      private

      def preview_url(attachment)
        return nil unless attachment.state_ready? && attachment.image.attached?

        routes.image_attachment_media_path(attachment, :original)
      end

      def failure(attachment)
        return nil unless attachment.state_failed?

        code = attachment.failure_code.presence || "upload_failed"
        # The copy and the retry verdict both come from the same place the
        # raise used, so a replayed failure reads exactly like the response the
        # composer already saw and never offers Retry for bytes the server will
        # keep rejecting.
        { code: code, message: Error.message_for(code), retryable: Error::RETRYABLE_CODES.include?(code) }
      end

      def routes
        Rails.application.routes.url_helpers
      end
    end
  end
end
