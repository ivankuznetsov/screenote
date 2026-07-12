# frozen_string_literal: true

require "tempfile"

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
      def call(image:, io:, declared_content_type:, declared_length: nil)
        new(image:, io:, declared_content_type:, declared_length:).call
      end
    end

    def initialize(image:, io:, declared_content_type:, declared_length: nil)
      @image = image
      @io = io
      @declared_content_type = declared_content_type.to_s.downcase
      @declared_length = declared_length
    end

    def call
      validate_headers!

      Tempfile.create("screenote-upload", Rails.root.join("tmp")) do |tempfile|
        tempfile.binmode
        content_sha256 = stream_to!(tempfile)
        detected_content_type = detect_content_type!(tempfile)
        validate_identity!(detected_content_type, content_sha256)
        persist!(tempfile, detected_content_type)
      end
    end

    private

    attr_reader :image, :io, :declared_content_type, :declared_length

    def validate_headers!
      unless declared_content_type.in?(ScreenshotImage::ALLOWED_CONTENT_TYPES)
        invalid!("Content-Type must be image/png or image/jpeg", code: "invalid_content_type")
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
      if detected_content_type != declared_content_type || detected_content_type != image.expected_content_type
        invalid!("Detected image type does not match the prepared and declared content type", code: "content_type_mismatch")
      end
      return if content_sha256 == image.content_sha256

      raise Error.new("Image bytes do not match the prepared content digest", code: "content_digest_mismatch", status: :conflict)
    end

    def persist!(tempfile, content_type)
      operation = nil
      enqueue_processing = false

      image.with_lock do
        ensure_manifest_identity!

        if image.image.attached?
          if image.status_failed?
            image.update!(status: :pending)
            operation = "processing_retried"
            enqueue_processing = true
          else
            operation = "already_uploaded"
          end
        else
          tempfile.rewind
          extension = content_type == "image/jpeg" ? "jpg" : "png"
          image.image.attach(
            io: tempfile,
            filename: "snapshot-image-#{image.id}.#{extension}",
            content_type: content_type
          )
          image.save!
          operation = "uploaded"
          enqueue_processing = true
        end
      end

      image.ensure_dimension_processing if enqueue_processing
      Result.new(image: image.reload, operation: operation)
    end

    def ensure_manifest_identity!
      return if image.screenshot.snapshot&.manifest_backed? && image.content_sha256.present? && image.expected_content_type.present?

      raise Error.new("Screenshot image is not prepared for manifest upload", code: "not_prepared", status: :unprocessable_entity)
    end

    def invalid!(message, code:)
      raise Error.new(message, code: code, status: :unprocessable_entity)
    end
  end
end
