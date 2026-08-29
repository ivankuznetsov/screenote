# frozen_string_literal: true

module ImageAttachmentDrafts
  class BatchesController < BaseController
    def create
      project = find_project!
      enforce_outstanding_draft_caps!

      batch = ImageAttachmentBatch.create!(user: Current.user, project: project)
      render_batch(batch, status: :created)
    end

    # Resume is what a reconnecting composer calls: it re-reads server state
    # rather than trusting anything the page still holds locally.
    def show
      render_batch(find_batch!)
    end

    private

    # Caps that hold even when the recurring cleanup supervisor is unhealthy.
    def enforce_outstanding_draft_caps!
      outstanding = Current.user.image_attachment_batches.outstanding.where("expires_at > ?", Time.current)

      if outstanding.count >= ImageAttachmentBatch::MAX_OPEN_PER_USER
        raise ImageAttachments::Error.new(
          "You have too many unfinished uploads. Finish or discard one first.",
          code: "too_many_open_batches"
        )
      end

      outstanding_bytes = ImageAttachment.where(image_attachment_batch: outstanding).sum(:byte_size)
      return if outstanding_bytes < ImageAttachmentBatch::MAX_OUTSTANDING_DRAFT_BYTES

      raise ImageAttachments::Error.new(
        "You have too many unfinished uploads. Finish or discard one first.",
        code: "draft_storage_exhausted"
      )
    end
  end
end
