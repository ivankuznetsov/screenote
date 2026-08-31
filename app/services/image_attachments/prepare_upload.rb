# frozen_string_literal: true

require "digest"
require "tempfile"
require "vips"

module ImageAttachments
  # Verifies one image upload and owns its temporary resources until a caller
  # either adopts the staged blob or cleans the result up.
  class PrepareUpload
    CHUNK_SIZE = 64.kilobytes
    PNG_SIGNATURE = "\x89PNG\r\n\x1A\n".b.freeze
    JPEG_SIGNATURE = "\xFF\xD8".b.freeze
    JPEG_START_OF_SCAN = 0xDA
    JPEG_END_OF_IMAGE = 0xD9

    class Result
      attr_reader :tempfile, :media_type, :byte_size, :width, :height, :sha256, :blob

      def initialize(tempfile:, media_type:, byte_size:, width:, height:, sha256:)
        @tempfile = tempfile
        @media_type = media_type
        @byte_size = byte_size
        @width = width
        @height = height
        @sha256 = sha256
        @blob = nil
        @blob_adopted = false
        @cleaned = false
      end

      def path
        tempfile.path
      end

      def read
        ensure_open!
        tempfile.rewind
        tempfile.read
      ensure
        tempfile.rewind unless tempfile.closed?
      end

      def stage!(record:, filename:)
        ensure_open!
        raise "prepared upload already has a staged blob" if blob

        tempfile.rewind
        @blob = ActiveStorage::Blob.create_after_unfurling!(
          io: tempfile,
          filename: filename,
          content_type: media_type,
          identify: false,
          record: record
        )
        tempfile.rewind
        blob.upload_without_unfurling(tempfile)
        tempfile.rewind
        blob
      rescue StandardError
        discard_unadopted_blob
        raise
      end

      def adopt_blob!
        raise "prepared upload has no staged blob" unless blob

        @blob_adopted = true
        blob
      end

      def cleanup
        return if @cleaned

        @cleaned = true
        discard_unadopted_blob unless @blob_adopted
      ensure
        tempfile.close! unless tempfile.closed?
      end

      private

      def ensure_open!
        raise IOError, "prepared upload is closed" if @cleaned || tempfile.closed?
      end

      def discard_unadopted_blob
        return unless blob

        PurgeBlob.call(blob)
      ensure
        @blob = nil unless @blob_adopted
      end
    end

    class << self
      def call(**kwargs)
        new(**kwargs).call
      end

      def validate_declarations!(declared_content_type:, declared_length:)
        content_type = declared_content_type.to_s.downcase.presence
        if content_type.present? && !content_type.in?(ImageAttachment::ALLOWED_CONTENT_TYPES)
          raise Error.new(code: "invalid_content_type")
        end
        return if declared_length.nil? || declared_length <= ImageAttachment::MAX_FILE_SIZE

        raise Error.new(code: "file_too_large")
      end
    end

    def initialize(io:, declared_content_type: nil, declared_length: nil, filename: nil, decoder_key: nil)
      @io = io
      @declared_content_type = declared_content_type.to_s.downcase.presence
      @declared_length = declared_length
      @filename = filename.to_s.presence
      @decoder_key = decoder_key
    end

    def call
      self.class.validate_declarations!(declared_content_type:, declared_length:)
      tempfile = Tempfile.new([ "screenote-attachment-#{Process.pid}-", ".image" ], Rails.root.join("tmp"))
      tempfile.binmode
      byte_size, sha256 = stream_to!(tempfile)
      media_type = detect_media_type!(tempfile)
      validate_declared_identity!(media_type)
      validate_complete_stream!(tempfile, media_type)
      width, height = decode!(tempfile)
      tempfile.rewind

      Result.new(tempfile:, media_type:, byte_size:, width:, height:, sha256:)
    rescue StandardError
      tempfile&.close!
      raise
    end

    private

    attr_reader :io, :declared_content_type, :declared_length, :filename, :decoder_key

    def stream_to!(tempfile)
      digest = Digest::SHA256.new
      total = 0

      # IO#read(n) answers nil at EOF; whitespace and an empty chunk are still
      # byte input supplied by the caller and must not be treated as absence.
      while (chunk = io.read(CHUNK_SIZE))
        total += chunk.bytesize
        invalid!("file_too_large") if total > ImageAttachment::MAX_FILE_SIZE
        digest.update(chunk)
        tempfile.write(chunk)
      end
      invalid!("empty_file") if total.zero?

      tempfile.flush
      [ total, digest.hexdigest ]
    end

    def detect_media_type!(tempfile)
      tempfile.rewind
      detected = Marcel::MimeType.for(tempfile)
      invalid!("invalid_image", Error::UNSUPPORTED_MEDIA_TYPE) unless
        detected.in?(ImageAttachment::ALLOWED_CONTENT_TYPES)
      detected
    end

    def validate_declared_identity!(media_type)
      invalid!("content_type_mismatch") if declared_content_type.present? && declared_content_type != media_type

      extension = File.extname(filename.to_s).delete_prefix(".").downcase
      return if extension.blank?
      return if ImageAttachment::ALLOWED_EXTENSIONS.fetch(media_type, []).include?(extension)

      invalid!("extension_mismatch")
    end

    # libvips validates the decoded picture but stops at the container's end
    # marker. Walk the container too so bytes appended after a valid image are
    # never stored and served back through the original/download routes.
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

    def webp_ends_at_eof?(file)
      size = file.size
      header = read_at(file, 0, 12)
      return false unless header && header.bytesize == 12
      return false unless header.byteslice(0, 4) == "RIFF" && header.byteslice(8, 4) == "WEBP"

      declared = header.byteslice(4, 4).unpack1("V")
      declared + 8 == size || (declared.odd? && declared + 9 == size)
    end

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
      ImageDecoding::Guard.synchronize(key: decoder_key) do
        decoded = Vips::Image.new_from_file(tempfile.path, access: :sequential, fail_on: :warning)
        width = decoded.width
        height = decoded.height
        validate_dimensions!(width, height)
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

    def invalid!(code, message = nil)
      raise Error.new(message, code: code)
    end
  end
end
