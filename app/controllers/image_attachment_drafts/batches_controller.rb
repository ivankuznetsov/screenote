# frozen_string_literal: true

module ImageAttachmentDrafts
  class BatchesController < BaseController
    # The composer supplies its own idempotency key, so a retry after a lost
    # response resumes the batch that key already opened instead of spending
    # another of the six open batches an account is allowed.
    def create
      batch = ImageAttachmentBatch.open_for!(
        user: Current.user,
        project: find_project!,
        client_key: params[:client_key]
      )
      render_batch(batch, status: batch.previously_new_record? ? :created : :ok)
    end

    # Resume is what a reconnecting composer calls: it re-reads server state
    # rather than trusting anything the page still holds locally. A batch that
    # has expired or been claimed is refused here rather than restored as ready:
    # media, upload, and claim all reject it, so answering 200 would only enable
    # a submission that is certain to fail.
    def show
      batch = find_batch!
      raise ImageAttachments::Error.new(code: "batch_unusable") unless batch.usable?

      render_batch(batch)
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
