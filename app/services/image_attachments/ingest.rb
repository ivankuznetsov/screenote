# frozen_string_literal: true

module ImageAttachments
  # Streams one composer upload into a draft batch.
  #
  # The uploading row is persisted before any byte is read so that claim,
  # cleanup, and the composer can observe every in-flight or failed item. The
  # expensive work — streaming, byte-derived type detection, and a full decode
  # through the global two-slot guard — happens with no row lock held. Only the
  # aggregate recheck and the state transition run inside the batch lock.
  class Ingest
    Result = Data.define(:attachment)

    class << self
      def call(**kwargs)
        new(**kwargs).call
      end
    end

    def initialize(batch:, io:, client_key:, declared_content_type: nil, declared_length: nil, filename: nil)
      @batch = batch
      @io = io
      @client_key = client_key.to_s
      @declared_content_type = declared_content_type
      @declared_length = declared_length
      @filename = filename
    end

    def call
      validate_request!
      attachment = reserve_slot!
      # A retry that lost only its response finds its slot already finished.
      # Replaying it must not reopen the row or replace the stored blob.
      return Result.new(attachment: attachment) if attachment.state_ready?

      begin
        prepared = PrepareUpload.call(
          io:,
          declared_content_type:,
          declared_length:,
          filename:,
          decoder_key: "image_attachment_batch:#{batch.id}"
        )
        attachment = commit!(attachment, prepared)

        Result.new(attachment: attachment)
      rescue Error => error
        record_failure(attachment, error)
        raise
      rescue StandardError => error
        # Storage and IO failures still answer the composer with the shared
        # machine code and actionable text; the cause goes to monitoring.
        Screenote::Monitoring.notify(error, context: { image_attachment_batch_id: batch.id })
        failure = Error.new(code: "upload_failed", status: :internal_server_error)
        record_failure(attachment, failure)
        raise failure
      ensure
        prepared&.cleanup
      end
    end

    private

    attr_reader :batch, :io, :client_key, :declared_content_type, :declared_length, :filename

    def validate_request!
      invalid!("batch_unusable") unless batch.usable?
      invalid!("missing_client_key") if client_key.blank?
      invalid!("invalid_client_key") if client_key.length > 64

      PrepareUpload.validate_declarations!(declared_content_type:, declared_length:)
    end

    # Reserving the slot up front means a client that dies mid-stream still
    # leaves an observable row that cleanup can reclaim and that the composer
    # counts against the five-file limit.
    def reserve_slot!
      batch.with_lock do
        ensure_usable!
        existing = batch.image_attachments.find_by(client_key: client_key)

        if existing
          raise Error.new(code: "attachment_removed", status: :not_found) if existing.removal_tombstone?

          # Retry reuses the client idempotency key and therefore its slot. A
          # slot that already finished is returned exactly as it stands.
          existing.update!(state: :uploading, failure_code: nil) unless existing.state_ready?
          next existing
        end

        invalid!("too_many_files") if batch.image_attachments.active_drafts.count >= ImageAttachment::MAX_FILES

        batch.image_attachments.create!(
          user_id: batch.user_id,
          project_id: batch.project_id,
          client_key: client_key,
          state: :uploading
        )
      end
    end

    def commit!(attachment, prepared)
      extension = ImageAttachment::ALLOWED_EXTENSIONS.fetch(prepared.media_type).first
      blob = prepared.stage!(record: attachment, filename: "image-attachment-#{attachment.id}.#{extension}")

      # The account row is the serialization point for the scheduler-
      # independent byte ceiling across every open batch. Taking it before the
      # batch also agrees with open_for! and account deletion, avoiding a
      # user/batch lock inversion.
      ImageAttachment.transaction do
        User.lock.find(batch.user_id)
        batch.lock!
        ensure_usable!
        # Remove and cleanup destroy the reserved row without this request
        # knowing. Re-resolving it under the batch lock — the same lock both of
        # those take first — is what stops a commit from binding bytes the
        # composer already discarded onto a row a claim would then attach.
        attachment = ensure_still_reserved!(attachment)
        ensure_slot_available!(attachment)
        ensure_total_within_limit!(attachment, prepared.byte_size)
        ensure_outstanding_drafts_within_limit!(attachment, prepared.byte_size)

        attachment.image.attach(blob)
        attachment.update!(
          state: :ready,
          failure_code: nil,
          media_type: prepared.media_type,
          width: prepared.width,
          height: prepared.height,
          byte_size: prepared.byte_size
        )
        # The expiry bump belongs to the same locked transition. Renewing it
        # after the lock is released leaves a window in which cleanup can take
        # the batch lock, observe the old expiry, and destroy a draft that has
        # just become ready.
        batch.touch_activity!
      end
      # Only a committed transaction owns the blob. Adopting it inside the
      # block would skip cleanup if COMMIT itself raises and rolls the row back.
      prepared.adopt_blob!
      attachment
    end

    def ensure_usable!
      return if batch.reload.usable?

      invalid!("batch_unusable")
    end

    def ensure_still_reserved!(attachment)
      current = batch.image_attachments.find_by(id: attachment.id)
      return current if current && !current.removal_tombstone?

      raise Error.new(code: "attachment_removed", status: :not_found)
    end

    # Counts the same rows the reservation side counts: a removal tombstone is
    # no longer part of the composer, so remove-then-replace must not be
    # rejected here after the replacement has already been decoded.
    def ensure_slot_available!(attachment)
      others = batch.image_attachments.active_drafts.where.not(id: attachment.id).count
      return if others < ImageAttachment::MAX_FILES

      invalid!("too_many_files")
    end

    def ensure_total_within_limit!(attachment, byte_size)
      others = batch.total_byte_size(excluding: attachment.id)
      return if others + byte_size <= ImageAttachment::MAX_TOTAL_BYTES

      invalid!("batch_too_large")
    end

    # The per-account outstanding cap is enforced again here, not only when a
    # batch is opened: six empty batches must not be fillable past the ceiling
    # that keeps a stopped cleanup supervisor from parking unbounded bytes.
    def ensure_outstanding_drafts_within_limit!(attachment, byte_size)
      others = ImageAttachmentBatch.outstanding_draft_bytes(batch.user_id, excluding: attachment.id)
      return if others + byte_size <= ImageAttachmentBatch::MAX_OUTSTANDING_DRAFT_BYTES

      invalid!("draft_storage_exhausted")
    end

    # A timed-out or aborted attempt shares its slot with the retry that
    # supersedes it, and with a removal that may have tombstoned it. Once the
    # row is ready the upload it names has already succeeded, so a late failure
    # from the disconnected attempt must not un-ready it and block the post with
    # `attachments_not_ready`.
    #
    # Reading the state and then writing it are two statements, so the retry can
    # commit `ready` between them. The write is therefore conditional on the row
    # still being an uploading draft: the database decides, and a stale attempt
    # that loses simply updates nothing.
    def record_failure(attachment, error)
      return unless attachment&.persisted?

      ImageAttachment
        .where(id: attachment.id, state: ImageAttachment.states[:uploading])
        .where.not(image_attachment_batch_id: nil)
        .update_all(
          state: ImageAttachment.states[:failed],
          failure_code: error.code,
          updated_at: Time.current
        )
    end

    def invalid!(code, message = nil)
      raise Error.new(message, code: code)
    end
  end
end
