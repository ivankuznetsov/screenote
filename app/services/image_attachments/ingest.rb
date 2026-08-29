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

      begin
        Tempfile.create([ "screenote-attachment-#{Process.pid}-", ".image" ], Rails.root.join("tmp")) do |tempfile|
          tempfile.binmode
          byte_size = stream_to!(tempfile)
          media_type = detect_media_type!(tempfile)
          validate_declared_identity!(media_type)
          width, height = decode!(tempfile)
          commit!(attachment, tempfile, media_type:, byte_size:, width:, height:)
        end

        Result.new(attachment: attachment)
      rescue Error => error
        record_failure(attachment, error)
        raise
      rescue StandardError
        record_failure(attachment, Error.new("Upload failed", code: "upload_failed"))
        raise
      end
    end

    private

    attr_reader :batch, :io, :client_key, :declared_content_type, :declared_length, :filename

    def validate_request!
      invalid!("This upload session expired. Reload the page and try again.", code: "batch_unusable") unless
        batch.usable?
      invalid!("Upload is missing its client key", code: "missing_client_key") if client_key.blank?
      invalid!("Upload client key is too long", code: "invalid_client_key") if client_key.length > 64

      if declared_content_type.present? && !declared_content_type.in?(ImageAttachment::ALLOWED_CONTENT_TYPES)
        invalid!("Attachments must be PNG, JPEG, or WebP images.", code: "invalid_content_type")
      end
      return if declared_length.nil? || declared_length <= ImageAttachment::MAX_FILE_SIZE

      invalid!(too_large_message, code: "file_too_large")
    end

    # Reserving the slot up front means a client that dies mid-stream still
    # leaves an observable row that cleanup can reclaim and that the composer
    # counts against the five-file limit.
    def reserve_slot!
      batch.with_lock do
        ensure_usable!
        existing = batch.image_attachments.find_by(client_key: client_key)

        if existing
          # Retry reuses the client idempotency key and therefore its slot.
          existing.update!(state: :uploading, failure_code: nil)
          next existing
        end

        if batch.image_attachments.count >= ImageAttachment::MAX_FILES
          invalid!("You can attach up to #{ImageAttachment::MAX_FILES} images.", code: "too_many_files")
        end

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
        invalid!(too_large_message, code: "file_too_large") if total > ImageAttachment::MAX_FILE_SIZE
        tempfile.write(chunk)
      end
      invalid!("The upload was empty.", code: "empty_file") if total.zero?

      tempfile.flush
      total
    end

    def detect_media_type!(tempfile)
      tempfile.rewind
      detected = Marcel::MimeType.for(tempfile)
      unless detected.in?(ImageAttachment::ALLOWED_CONTENT_TYPES)
        invalid!("Attachments must be PNG, JPEG, or WebP images.", code: "invalid_image")
      end
      detected
    end

    # A declaration is optional, but where the browser supplies one it must
    # agree with the bytes and with the filename extension.
    def validate_declared_identity!(media_type)
      if declared_content_type.present? && declared_content_type != media_type
        invalid!("The file contents do not match its declared type.", code: "content_type_mismatch")
      end

      extension = File.extname(filename.to_s).delete_prefix(".").downcase
      return if extension.blank?
      return if ImageAttachment::ALLOWED_EXTENSIONS.fetch(media_type, []).include?(extension)

      invalid!("The file contents do not match its extension.", code: "extension_mismatch")
    end

    def decode!(tempfile)
      ImageDecoding::Guard.synchronize do
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
      raise Error.new(
        "The image processor is busy. Retry this upload.",
        code: "decoder_busy",
        status: :service_unavailable
      )
    rescue Vips::Error
      invalid!("That image could not be read.", code: "invalid_image")
    end

    def validate_dimensions!(width, height)
      if width > ImageAttachment::MAX_DIMENSION || height > ImageAttachment::MAX_DIMENSION
        invalid!("Image dimensions exceed #{ImageAttachment::MAX_DIMENSION}px.", code: "image_dimensions_too_large")
      end
      return if width * height <= ImageAttachment::MAX_PIXELS

      invalid!("Image pixel count exceeds #{ImageAttachment::MAX_PIXELS}.", code: "image_pixels_too_large")
    end

    def commit!(attachment, tempfile, media_type:, byte_size:, width:, height:)
      blob = stage_blob!(attachment, tempfile, media_type)
      attached = false

      batch.with_lock do
        ensure_usable!
        ensure_slot_available!(attachment)
        ensure_total_within_limit!(attachment, byte_size)

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

      invalid!("This upload session expired. Reload the page and try again.", code: "batch_unusable")
    end

    def ensure_slot_available!(attachment)
      return if batch.image_attachments.where.not(id: attachment.id).count < ImageAttachment::MAX_FILES

      invalid!("You can attach up to #{ImageAttachment::MAX_FILES} images.", code: "too_many_files")
    end

    def ensure_total_within_limit!(attachment, byte_size)
      others = batch.total_byte_size(excluding: attachment.id)
      return if others + byte_size <= ImageAttachment::MAX_TOTAL_BYTES

      invalid!(
        "Attachments for one message can total at most #{ImageAttachment::MAX_TOTAL_BYTES / 1.megabyte}MB.",
        code: "batch_too_large"
      )
    end

    def record_failure(attachment, error)
      return unless attachment&.persisted?

      attachment.reload
      return unless attachment.draft?

      attachment.update_columns(
        state: ImageAttachment.states[:failed],
        failure_code: error.code,
        updated_at: Time.current
      )
    rescue ActiveRecord::RecordNotFound
      nil
    end

    def too_large_message
      "Each image must be #{ImageAttachment::MAX_FILE_SIZE / 1.megabyte}MB or smaller."
    end

    def invalid!(message, code:)
      raise Error.new(message, code: code)
    end
  end
end
