# frozen_string_literal: true

# Shared posting contract for the native composers.
#
# A form supplies exactly one draft batch public ID and nothing else about the
# attachments: uploader, project, sizes, types, row IDs, and states all come
# from the server. Ordinary validation failures answer with 422 plus enough
# state for the still-mounted composer to restore itself, which is what keeps a
# rejected message from losing the text and the images the person just added.
module ImageAttachmentSubmission
  extend ActiveSupport::Concern

  included do
    rescue_from ImageAttachments::Error, with: :render_attachment_error
  end

  private

  def submission_batch(project)
    public_id = params[:image_attachment_batch_id].presence
    return nil if public_id.blank?

    batch = ImageAttachmentBatch.find_by(public_id: public_id.to_s)
    unless batch && batch.user_id == Current.user.id && batch.project_id == project.id
      raise ImageAttachments::Error.new(code: "batch_not_owned")
    end

    batch
  end

  def submitted_batch_public_id
    params[:image_attachment_batch_id].presence&.to_s
  end

  def ready_attachment_ids(batch)
    return [] unless batch

    batch.image_attachments.state_ready.ordered.pluck(:id)
  end

  def render_submission_error(messages, code: "validation_failed", batch: nil)
    render json: {
      error: { code: code, message: messages.first.to_s },
      errors: messages,
      form: composer_state(batch)
    }, status: :unprocessable_entity
  end

  def render_attachment_error(error)
    respond_to do |format|
      format.json do
        render json: {
          error: { code: error.code, message: error.message, retryable: error.retryable? },
          errors: [ error.message ],
          form: composer_state(submission_batch_for_state)
        }, status: error.status
      end
      format.html { redirect_to attachment_error_redirect_path, alert: error.message }
    end
  end

  def submission_batch_for_state
    ImageAttachmentBatch.find_by(public_id: submitted_batch_public_id.to_s, user_id: Current.user.id)
  end

  def composer_state(batch)
    {
      image_attachment_batch_id: submitted_batch_public_id,
      ready_attachment_ids: ready_attachment_ids(batch)
    }
  end
end
