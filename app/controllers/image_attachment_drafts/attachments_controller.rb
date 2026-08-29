# frozen_string_literal: true

module ImageAttachmentDrafts
  class AttachmentsController < BaseController
    def create
      batch = find_batch!
      upload = params[:file]
      raise ImageAttachments::Error.new("No file was uploaded.", code: "missing_file") unless upload.respond_to?(:read)

      result = ImageAttachments::Ingest.call(
        batch: batch,
        io: upload,
        client_key: params[:client_key],
        declared_content_type: upload.try(:content_type),
        declared_length: request.content_length,
        filename: upload.try(:original_filename)
      )

      render_attachment(result.attachment, status: :created)
    end

    # Alt text is authored while the image is still a draft. After the message
    # is posted the description is part of the historical record.
    def update
      batch = find_batch!
      attachment = batch.image_attachments.find_by(id: params[:id])
      raise ActiveRecord::RecordNotFound unless attachment

      attachment.update!(alt_text: params.require(:image_attachment).permit(:alt_text)[:alt_text])
      batch.touch_activity! if batch.usable?
      render_attachment(attachment)
    end

    def destroy
      batch = find_batch!
      ImageAttachments::RemoveAttachment.call(batch: batch, attachment_id: params[:id])

      render_batch(batch.reload)
    end
  end
end
