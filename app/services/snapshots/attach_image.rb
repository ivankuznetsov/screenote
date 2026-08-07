# frozen_string_literal: true

require "tempfile"
require "vips"

module Snapshots
  class AttachImage
    CHUNK_SIZE = 64.kilobytes

    Result = Data.define(:image, :operation)

    class Error < StandardError
      attr_reader :code, :status

      def initialize(message, code:, status:)
        super(message)
        @code = code
        @status = status
      end
    end

    class << self
      def call(image:, io:, declared_content_type:, declared_length: nil, filename: nil, replace_existing: false,
        schedule_processing: true)
        new(
          image:, io:, declared_content_type:, declared_length:, filename:, replace_existing:, schedule_processing:
        ).call
      end
    end

    def initialize(image:, io:, declared_content_type:, declared_length: nil, filename: nil, replace_existing: false,
      schedule_processing: true)
      @image = image
      @io = io
      @declared_content_type = declared_content_type.to_s.downcase
      @declared_length = declared_length
      @filename = filename.to_s.presence
      @replace_existing = replace_existing
      @schedule_processing = schedule_processing
    end

    def call
      validate_headers!

      Tempfile.create([ "screenote-upload-#{Process.pid}-", ".image" ], Rails.root.join("tmp")) do |tempfile|
        tempfile.binmode
        content_sha256 = stream_to!(tempfile)
        detected_content_type = detect_content_type!(tempfile)
        validate_identity!(detected_content_type, content_sha256)
        validate_complete_image!(tempfile)
        persist!(tempfile, detected_content_type)
      end
    end

    private

    attr_reader :image, :io, :declared_content_type, :declared_length, :filename

    def validate_headers!
      unless declared_content_type.in?(ScreenshotImage::ALLOWED_CONTENT_TYPES)
        invalid!("Invalid mime type. Must be a PNG or JPEG", code: "invalid_content_type")
      end
      return if declared_length.nil? || declared_length <= ScreenshotImage::MAX_FILE_SIZE

      invalid!("File is too large", code: "file_too_large")
    end

    def stream_to!(tempfile)
      digest = Digest::SHA256.new
      total = 0

      while (chunk = io.read(CHUNK_SIZE)).present?
        total += chunk.bytesize
        invalid!("File is too large", code: "file_too_large") if total > ScreenshotImage::MAX_FILE_SIZE
        digest.update(chunk)
        tempfile.write(chunk)
      end
      invalid!("Request body is empty", code: "empty_body") if total.zero?

      tempfile.flush
      digest.hexdigest
    end

    def detect_content_type!(tempfile)
      tempfile.rewind
      detected = Marcel::MimeType.for(tempfile)
      unless detected.in?(ScreenshotImage::ALLOWED_CONTENT_TYPES)
        invalid!("Request body is not a valid PNG or JPEG", code: "invalid_image")
      end
      detected
    end

    def validate_identity!(detected_content_type, content_sha256)
      if detected_content_type != declared_content_type
        invalid!("Detected image type does not match the declared content type", code: "content_type_mismatch")
      end
      if image.expected_content_type.present? && detected_content_type != image.expected_content_type
        invalid!("Detected image type does not match the prepared and declared content type", code: "content_type_mismatch")
      end
      return if image.content_sha256.blank? || content_sha256 == image.content_sha256

      raise Error.new("Image bytes do not match the prepared content digest", code: "content_digest_mismatch", status: :conflict)
    end

    def validate_complete_image!(tempfile)
      ImageDecoding::Guard.synchronize do
        decoded = Vips::Image.new_from_file(tempfile.path, access: :sequential, fail_on: :warning)
        width = decoded.width
        height = decoded.height
        validate_dimensions!(width, height)

        # Vips image loading is lazy. Reducing the whole image forces every
        # scanline through the decoder while the global resource guard is held.
        decoded.avg
      end
    rescue ImageDecoding::Guard::Busy
      raise Error.new("Image decoder is busy; retry the upload", code: "decoder_busy", status: :service_unavailable)
    rescue Vips::Error
      invalid!("Request body is not a valid PNG or JPEG", code: "invalid_image")
    end

    def validate_dimensions!(width, height)
      if width > ScreenshotImage::MAX_DIMENSION || height > ScreenshotImage::MAX_DIMENSION
        invalid!("Image dimensions exceed #{ScreenshotImage::MAX_DIMENSION}px", code: "image_dimensions_too_large")
      end
      return if width * height <= ScreenshotImage::MAX_PIXELS

      invalid!("Image pixel count exceeds #{ScreenshotImage::MAX_PIXELS}", code: "image_pixels_too_large")
    end

    def persist!(tempfile, content_type)
      operation = nil
      enqueue_processing = false
      staged_blob = stage_blob!(tempfile, content_type) if replace_existing? || !image.image.attached?
      staged_blob_attached = false
      use_staged_blob = false

      image.with_lock do
        ensure_manifest_identity!

        if replace_existing?
          replacing_attachment = image.image.attached?
          attach_staged_blob!(staged_blob)
          image.update!(status: :pending, width: nil, height: nil)
          operation = replacing_attachment ? "replaced" : "uploaded"
          enqueue_processing = true
          use_staged_blob = true
        elsif image.image.attached?
          if image.status_failed?
            image.update!(status: :pending)
            operation = "processing_retried"
            enqueue_processing = true
          else
            operation = "already_uploaded"
          end
        else
          attach_staged_blob!(staged_blob)
          image.save!
          operation = "uploaded"
          enqueue_processing = true
          use_staged_blob = true
        end
      end

      staged_blob_attached = use_staged_blob
      discard_staged_blob!(staged_blob) if staged_blob && !staged_blob_attached
      image.ensure_dimension_processing if enqueue_processing && schedule_processing?
      Result.new(image: image, operation: operation)
    rescue StandardError
      discard_staged_blob_after_error(staged_blob) if staged_blob && !staged_blob_attached
      raise
    end

    def stage_blob!(tempfile, content_type)
      tempfile.rewind
      extension = content_type == "image/jpeg" ? "jpg" : "png"
      blob = ActiveStorage::Blob.create_after_unfurling!(
        io: tempfile,
        filename: filename || "snapshot-image-#{image.id}.#{extension}",
        content_type: content_type,
        identify: false,
        record: image
      )
      delete_staged_object_after_rollback(blob)
      tempfile.rewind
      blob.upload_without_unfurling(tempfile)
      blob
    rescue StandardError
      discard_staged_blob_after_error(blob) if blob
      raise
    end

    def attach_staged_blob!(blob)
      raise "validated screenshot upload has no staged blob" unless blob

      # Passing a pre-uploaded Blob makes Active Storage's after_commit upload
      # a no-op. The database can therefore never commit an attachment whose
      # only source bytes lived in an already-closed request tempfile.
      image.image.attach(blob)
    end

    def delete_staged_object_after_rollback(blob)
      transaction = image.class.current_transaction
      return unless transaction.open?

      transaction.after_rollback do
        blob.service.delete(blob.key)
      rescue StandardError => error
        Rails.logger.error("Failed to remove a rolled-back screenshot object (#{error.class})")
      end
    end

    def discard_staged_blob!(blob)
      blob.purge
    end

    def discard_staged_blob_after_error(blob)
      discard_staged_blob!(blob)
    rescue StandardError => error
      Rails.logger.error("Failed to discard an unattached screenshot blob (#{error.class})")
    end

    def replace_existing?
      @replace_existing
    end

    def schedule_processing?
      @schedule_processing
    end

    def ensure_manifest_identity!
      return unless image.screenshot.snapshot&.manifest_backed?
      return if image.content_sha256.present? && image.expected_content_type.present?

      raise Error.new("Screenshot image is not prepared for manifest upload", code: "not_prepared", status: :unprocessable_entity)
    end

    def invalid!(message, code:)
      raise Error.new(message, code: code, status: :unprocessable_entity)
    end
  end
end
