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
    PNG_SIGNATURE = "\x89PNG\r\n\x1A\n".b.freeze
    JPEG_SIGNATURE = "\xFF\xD8".b.freeze
    JPEG_START_OF_SCAN = 0xDA
    JPEG_END_OF_IMAGE = 0xD9

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
          validate_complete_stream!(tempfile, media_type)
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

      # IO#read(n) answers nil at EOF; a chunk of whitespace bytes is real
      # data, so only nil may end the loop.
      while (chunk = io.read(CHUNK_SIZE))
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

    # A full decode proves the leading picture is real; it says nothing about
    # what follows the picture's own end marker. libvips stops decoding there,
    # so a valid PNG carrying an appended archive, script, or second file reads
    # as a perfectly good image and would be stored and served back byte for
    # byte. Each of the three accepted containers declares where it ends, so the
    # container is walked and its declared end has to be the end of the file.
    def validate_complete_stream!(tempfile, media_type)
      complete = case media_type
      when "image/png" then png_ends_at_eof?(tempfile)
      when "image/jpeg" then jpeg_ends_at_eof?(tempfile)
      when "image/webp" then webp_ends_at_eof?(tempfile)
      else false
      end
      return if complete

      invalid!("invalid_image")
    end

    # PNG is a chunk list: each chunk is a 4-byte length, a 4-byte type, the
    # data, and a 4-byte CRC. Walking it lands exactly on IEND, and IEND has to
    # be the last thing in the file.
    def png_ends_at_eof?(file)
      size = file.size
      return false unless read_at(file, 0, 8) == PNG_SIGNATURE

      offset = 8
      while offset + 8 <= size
        header = read_at(file, offset, 8)
        return false unless header && header.bytesize == 8
        return false unless header.byteslice(4, 4).match?(/\A[A-Za-z]{4}\z/)

        offset += 12 + header.unpack1("N")
        return offset == size if header.byteslice(4, 4) == "IEND"
      end

      false
    end

    # RIFF states its own payload length. Anything past it is not part of the
    # image. The odd-length case allows the single pad byte RIFF appends to keep
    # the container word aligned.
    def webp_ends_at_eof?(file)
      size = file.size
      header = read_at(file, 0, 12)
      return false unless header && header.bytesize == 12
      return false unless header.byteslice(0, 4) == "RIFF" && header.byteslice(8, 4) == "WEBP"

      declared = header.byteslice(4, 4).unpack1("V")
      declared + 8 == size || (declared.odd? && declared + 9 == size)
    end

    # JPEG has no length field for its entropy-coded scans, so the segment list
    # is walked and each scan is scanned for the next real marker: inside
    # entropy data a literal 0xFF is stuffed as 0xFF00, and restart markers are
    # part of the scan, so anything else terminates it. EOI has to be the last
    # two bytes.
    def jpeg_ends_at_eof?(file)
      size = file.size
      return false unless read_at(file, 0, 2) == JPEG_SIGNATURE

      offset = 2
      while offset + 2 <= size
        marker = read_at(file, offset, 2)
        return false unless marker && marker.getbyte(0) == 0xFF

        code = marker.getbyte(1)
        offset += 2
        next if code == 0xFF || code == 0x01 || (0xD0..0xD7).cover?(code)
        return offset == size if code == JPEG_END_OF_IMAGE

        length = read_at(file, offset, 2)&.unpack1("n")
        return false if length.nil? || length < 2

        offset += length
        return false if offset > size

        if code == JPEG_START_OF_SCAN
          offset = jpeg_entropy_end(file, offset, size)
          return false unless offset
        end
      end

      false
    end

    def jpeg_entropy_end(file, offset, size)
      while offset < size
        chunk = read_at(file, offset, CHUNK_SIZE)
        return nil if chunk.nil? || chunk.empty?

        index = 0
        loop do
          found = chunk.index("\xFF".b, index)
          if found.nil?
            offset += chunk.bytesize
            break
          end

          following = chunk.getbyte(found + 1)
          if following.nil?
            # A 0xFF as the very last byte is truncated data; otherwise the
            # marker straddles this chunk, so the walk resumes on it.
            return nil if offset + found + 1 >= size

            offset += found
            break
          end
          return offset + found unless following.zero? || following == 0xFF ||
            (0xD0..0xD7).cover?(following)

          index = found + (following == 0xFF ? 1 : 2)
        end
      end

      nil
    end

    def read_at(file, offset, length)
      file.seek(offset)
      file.read(length)
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
        # The expiry bump belongs to the same locked transition. Renewing it
        # after the lock is released leaves a window in which cleanup can take
        # the batch lock, observe the old expiry, and destroy a draft that has
        # just become ready.
        batch.touch_activity!
      end
      # Only a committed transaction owns the blob. Setting this inside the
      # block would skip the purge when COMMIT itself raises and the row rolls
      # back to `uploading`, stranding staged bytes nothing reconciles.
      attached = true

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
      PurgeBlob.call(blob)
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
