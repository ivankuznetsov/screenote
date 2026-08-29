# frozen_string_literal: true

module ImageAttachmentDrafts
  class AttachmentsController < BaseController
    def create
      batch = find_batch!
      upload = params[:file]
      raise ImageAttachments::Error.new(code: "missing_file") unless upload.respond_to?(:read)

      result = ImageAttachments::Ingest.call(
        batch: batch,
        io: upload,
        client_key: params[:client_key],
        declared_content_type: upload.try(:content_type),
        # The envelope carries multipart framing as well as the bytes, so the
        # per-file ceiling is declared from the uploaded part's own size.
        declared_length: upload.try(:size),
        filename: upload.try(:original_filename)
      )

      render_attachment(result.attachment, status: :created)
    end

    # Alt text is authored while the image is still a draft. After the message
    # is posted the description is part of the historical record.
    def update
      attachment = ImageAttachments::WriteAltText.call(
        batch: find_batch!,
        attachment_id: params[:id],
        alt_text: params.require(:image_attachment).permit(:alt_text)[:alt_text]
      )

      render_attachment(attachment)
    end

    def destroy
      batch = find_batch!
      ImageAttachments::RemoveAttachment.call(batch: batch, attachment_id: params[:id])

      render_batch(batch.reload)
    end

    # The browser always knows its client key, including before an in-flight
    # POST has returned the numeric row ID. Reserving that key as removed makes
    # an abort/delete race deterministic instead of letting a ghost row reach
    # the next claim.
    def discard
      batch = find_batch!
      ImageAttachments::RemoveAttachment.call(
        batch: batch,
        client_key: params.require(:client_key).to_s
      )

      render_batch(batch.reload)
    end
  end
end
