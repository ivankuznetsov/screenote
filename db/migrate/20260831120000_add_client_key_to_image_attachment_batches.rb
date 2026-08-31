# frozen_string_literal: true

# A composer that loses the response to its batch creation has no way to ask
# whether the batch exists, so every retry used to consume one more of the six
# open batches an account is allowed. The mounted composer now supplies its own
# idempotency key and the server returns the batch that key already opened.
class AddClientKeyToImageAttachmentBatches < ActiveRecord::Migration[8.1]
  def change
    add_column :image_attachment_batches, :client_key, :string, limit: 64

    add_index :image_attachment_batches, %i[user_id client_key],
      unique: true,
      # Only an open batch reserves its key: once a batch is claimed the
      # composer has finished with it, and the next mounted composer is free to
      # present a fresh key without colliding with posted history.
      where: "client_key IS NOT NULL AND state = 0",
      name: "index_image_attachment_batches_on_user_and_client_key"
  end
end
