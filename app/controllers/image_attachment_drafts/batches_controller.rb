# frozen_string_literal: true

module ImageAttachmentDrafts
  class BatchesController < BaseController
    def create
      batch = ImageAttachmentBatch.open_for!(user: Current.user, project: find_project!)
      render_batch(batch, status: :created)
    end

    # Resume is what a reconnecting composer calls: it re-reads server state
    # rather than trusting anything the page still holds locally.
    def show
      render_batch(find_batch!)
    end

    # An explicit composer cancel discards its own unclaimed draft, which is
    # what makes the open-batch ceiling's "finish or discard one first" true.
    # Discarding an already claimed or already discarded batch is a no-op.
    def destroy
      ImageAttachments::DiscardBatch.call(batch: find_batch!)
      head :no_content
    end
  end
end
