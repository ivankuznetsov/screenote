# frozen_string_literal: true

require "tempfile"
require "vips"

module ImageAttachments
  # Streams one composer upload into a draft batch.
  #
  # The uploading row is persisted before any byte is read so that claim,
  # cleanup, and the composer can observe every in-flight or failed item. The
  # expensive work — streaming, byte-derived type detection, and a full decode
  # through the global two-slot guard — happens with no row lock held. Only the
  # aggregate recheck and the state transition run inside the batch lock.
  class Ingest
    CHUNK_SIZE = 64.kilobytes

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
      @declared_content_type = declared_content_type.to_s.downcase.presence
      @declared_length = declared_length
      @filename = filename.to_s.presence
    end

    def call
      validate_request!
      attachment = reserve_slot!
      # A retry that lost only its response finds its slot already finished.
      # Replaying it must not reopen the row or replace the stored blob.
      return Result.new(attachment: attachment) if attachment.state_ready?

      begin
        Tempfile.create([ "screenote-attachment-#{Process.pid}-", ".image" ], Rails.root.join("tmp")) do |tempfile|
          tempfile.binmode
          byte_size = stream_to!(tempfile)
          media_type = detect_media_type!(tempfile)
          validate_declared_identity!(media_type)
          width, height = decode!(tempfile)
          attachment = commit!(attachment, tempfile, media_type:, byte_size:, width:, height:)
        end

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
      end
    end

    private

    attr_reader :batch, :io, :client_key, :declared_content_type, :declared_length, :filename

    def validate_request!
      invalid!("batch_unusable") unless batch.usable?
      invalid!("missing_client_key") if client_key.blank?
      invalid!("invalid_client_key") if client_key.length > 64

      if declared_content_type.present? && !declared_content_type.in?(ImageAttachment::ALLOWED_CONTENT_TYPES)
        invalid!("invalid_content_type")
      end
      return if declared_length.nil? || declared_length <= ImageAttachment::MAX_FILE_SIZE

      invalid!("file_too_large")
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

    def stream_to!(tempfile)
      total = 0

      while (chunk = io.read(CHUNK_SIZE)).present?
        total += chunk.bytesize
        invalid!("file_too_large") if total > ImageAttachment::MAX_FILE_SIZE
        tempfile.write(chunk)
      end
      invalid!("empty_file") if total.zero?

      tempfile.flush
      total
    end

    def detect_media_type!(tempfile)
      tempfile.rewind
      detected = Marcel::MimeType.for(tempfile)
      invalid!("invalid_image", Error::UNSUPPORTED_MEDIA_TYPE) unless
        detected.in?(ImageAttachment::ALLOWED_CONTENT_TYPES)
      detected
    end

    # A declaration is optional, but where the browser supplies one it must
    # agree with the bytes and with the filename extension.
    def validate_declared_identity!(media_type)
      invalid!("content_type_mismatch") if declared_content_type.present? && declared_content_type != media_type

      extension = File.extname(filename.to_s).delete_prefix(".").downcase
      return if extension.blank?
      return if ImageAttachment::ALLOWED_EXTENSIONS.fetch(media_type, []).include?(extension)

      invalid!("extension_mismatch")
    end

    def decode!(tempfile)
      # Keyed on the batch so overlapping uploads for one composer — a retry
      # racing its aborted attempt, or a multi-file paste — decode one at a
      # time instead of occupying every global slot.
      ImageDecoding::Guard.synchronize(key: "image_attachment_batch:#{batch.id}") do
        decoded = Vips::Image.new_from_file(tempfile.path, access: :sequential, fail_on: :warning)
        width = decoded.width
        height = decoded.height
        validate_dimensions!(width, height)

        # Vips loading is lazy. Reducing the whole image forces every scanline
        # through the decoder while the global guard is held, so a truncated or
        # polyglot file cannot reach storage.
        decoded.avg
        [ width, height ]
      end
    rescue ImageDecoding::Guard::Busy
      raise Error.new(code: "decoder_busy", status: :service_unavailable)
    rescue Vips::Error
      invalid!("invalid_image")
    end

    def validate_dimensions!(width, height)
      if width > ImageAttachment::MAX_DIMENSION || height > ImageAttachment::MAX_DIMENSION
        invalid!("image_dimensions_too_large")
      end
      return if width * height <= ImageAttachment::MAX_PIXELS

      invalid!("image_pixels_too_large")
    end

    def commit!(attachment, tempfile, media_type:, byte_size:, width:, height:)
      blob = stage_blob!(attachment, tempfile, media_type)
      attached = false

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
        ensure_total_within_limit!(attachment, byte_size)
        ensure_outstanding_drafts_within_limit!(attachment, byte_size)

        attachment.image.attach(blob)
        attachment.update!(
          state: :ready,
          failure_code: nil,
          media_type: media_type,
          width: width,
          height: height,
          byte_size: byte_size
        )
        attached = true
      end

      batch.touch_activity!
      attachment
    ensure
      discard_blob(blob) if blob && !attached
    end

    def stage_blob!(attachment, tempfile, media_type)
      tempfile.rewind
      extension = ImageAttachment::ALLOWED_EXTENSIONS.fetch(media_type).first
      blob = ActiveStorage::Blob.create_after_unfurling!(
        io: tempfile,
        # The stored name is generated server-side; the client filename never
        # reaches storage or any rendered label.
        filename: "image-attachment-#{attachment.id}.#{extension}",
        content_type: media_type,
        identify: false,
        record: attachment
      )
      tempfile.rewind
      blob.upload_without_unfurling(tempfile)
      blob
    rescue StandardError
      discard_blob(blob) if blob
      raise
    end

    def discard_blob(blob)
      blob.purge
    rescue StandardError => error
      Rails.logger.error("Failed to discard an unattached image attachment blob (#{error.class})")
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

    def ensure_slot_available!(attachment)
      return if batch.image_attachments.where.not(id: attachment.id).count < ImageAttachment::MAX_FILES

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

    def record_failure(attachment, error)
      return unless attachment&.persisted?

      attachment.reload
      return unless attachment.draft?
      return if attachment.removal_tombstone?
      # A timed-out or aborted attempt shares its slot with the retry that
      # supersedes it. Once the row is ready the upload it names has already
      # succeeded, so a late failure from the disconnected attempt must not
      # un-ready it and block the post with `attachments_not_ready`.
      return if attachment.state_ready?

      attachment.update_columns(
        state: ImageAttachment.states[:failed],
        failure_code: error.code,
        updated_at: Time.current
      )
    rescue ActiveRecord::RecordNotFound
      nil
    end

    def invalid!(code, message = nil)
      raise Error.new(message, code: code)
    end
  end
end
