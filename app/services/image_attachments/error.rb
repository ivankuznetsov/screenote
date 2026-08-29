# frozen_string_literal: true

module ImageAttachments
  # Machine code plus actionable text. Controllers surface both; the code is
  # what the composer branches on, and `retryable` tells it whether the same
  # bytes are worth sending again.
  #
  # The copy for every code lives here so a raised failure and the same failure
  # replayed from a stored row can never drift apart, and so every limit in the
  # text is derived from the constant the server actually enforces.
  class Error < StandardError
    RETRYABLE_CODES = %w[decoder_busy storage_unavailable].freeze

    # Byte-sniffing rejects exactly the set the declared type check rejects, so
    # both report it with the same words.
    UNSUPPORTED_MEDIA_TYPE = "Attachments must be PNG, JPEG, or WebP images."

    MESSAGES = {
      "batch_unusable" => "This upload session expired. Reload the page and try again.",
      "batch_not_owned" => "These attachments belong to a different composer.",
      "missing_file" => "No file was uploaded.",
      "missing_client_key" => "Upload is missing its client key",
      "invalid_client_key" => "Upload client key is too long",
      "invalid_content_type" => UNSUPPORTED_MEDIA_TYPE,
      "invalid_image" => "That image could not be read.",
      "content_type_mismatch" => "The file contents do not match its declared type.",
      "extension_mismatch" => "The file contents do not match its extension.",
      "empty_file" => "The upload was empty.",
      "file_too_large" => "Each image must be #{ImageAttachment::MAX_FILE_SIZE / 1.megabyte}MB or smaller.",
      "batch_too_large" =>
        "Attachments for one message can total at most #{ImageAttachment::MAX_TOTAL_BYTES / 1.megabyte}MB.",
      "too_many_files" => "You can attach up to #{ImageAttachment::MAX_FILES} images.",
      "image_dimensions_too_large" => "Image dimensions exceed #{ImageAttachment::MAX_DIMENSION}px.",
      "image_pixels_too_large" => "Image pixel count exceeds #{ImageAttachment::MAX_PIXELS}.",
      "attachments_not_ready" => "Wait for every image to finish uploading.",
      "attachment_removed" => "That image was removed.",
      "too_many_open_batches" => "You have too many unfinished uploads. Finish or discard one first.",
      "draft_storage_exhausted" => "You have too many unfinished uploads. Finish or discard one first.",
      "decoder_busy" => "The image processor is busy. Retry this upload.",
      "upload_failed" => "The upload did not finish. Retry it."
    }.freeze

    attr_reader :code, :status

    def self.message_for(code)
      MESSAGES.fetch(code.to_s) { MESSAGES.fetch("upload_failed") }
    end

    def initialize(message = nil, code:, status: :unprocessable_entity)
      @code = code.to_s
      @status = status
      super(message.presence || self.class.message_for(@code))
    end

    def retryable?
      RETRYABLE_CODES.include?(code)
    end
  end
end
