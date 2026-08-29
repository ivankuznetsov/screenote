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
  end
end
