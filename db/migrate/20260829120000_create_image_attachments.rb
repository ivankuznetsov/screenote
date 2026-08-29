# frozen_string_literal: true

class CreateImageAttachments < ActiveRecord::Migration[8.1]
  BATCH_CLAIM_CHECK = <<~SQL.squish.freeze
    (state = 0 AND claimed_annotation_id IS NULL AND claimed_annotation_comment_id IS NULL) OR
    (state = 1 AND claimed_annotation_id IS NOT NULL AND claimed_annotation_comment_id IS NULL) OR
    (state = 1 AND claimed_annotation_id IS NULL AND claimed_annotation_comment_id IS NOT NULL)
  SQL

  PARENT_CHECK = <<~SQL.squish.freeze
    (image_attachment_batch_id IS NOT NULL AND annotation_id IS NULL AND annotation_comment_id IS NULL) OR
    (image_attachment_batch_id IS NULL AND annotation_id IS NOT NULL AND annotation_comment_id IS NULL) OR
    (image_attachment_batch_id IS NULL AND annotation_id IS NULL AND annotation_comment_id IS NOT NULL)
  SQL

  # A row that no longer belongs to a draft batch is part of a posted message.
  # Submitted attachments are therefore always fully decoded and measured.
  SUBMITTED_READY_CHECK = <<~SQL.squish.freeze
    image_attachment_batch_id IS NOT NULL OR
    (state = 1 AND media_type IS NOT NULL AND width IS NOT NULL AND height IS NOT NULL AND byte_size IS NOT NULL)
  SQL

  def change
    create_table :image_attachment_batches do |table|
      table.string :public_id, limit: 43, null: false
      table.references :user, null: false, foreign_key: { on_delete: :restrict }
      table.references :project, null: false, foreign_key: true
      table.integer :state, null: false, default: 0
      table.references :claimed_annotation, foreign_key: { to_table: :annotations }
      table.references :claimed_annotation_comment, foreign_key: { to_table: :annotation_comments }
      table.datetime :last_activity_at, null: false
      table.datetime :expires_at, null: false

      table.timestamps
    end

    add_index :image_attachment_batches, :public_id, unique: true
    add_index :image_attachment_batches, %i[user_id state]
    add_index :image_attachment_batches, %i[state expires_at]

    add_check_constraint :image_attachment_batches, "state IN (0, 1)",
      name: "image_attachment_batches_valid_state"
    add_check_constraint :image_attachment_batches, "expires_at > last_activity_at",
      name: "image_attachment_batches_future_expiry"
    add_check_constraint :image_attachment_batches, BATCH_CLAIM_CHECK,
      name: "image_attachment_batches_claim_state"

    create_table :image_attachments do |table|
      table.references :image_attachment_batch, foreign_key: true
      table.references :annotation, foreign_key: true
      table.references :annotation_comment, foreign_key: true
      table.references :user, null: false, foreign_key: { on_delete: :restrict }
      table.references :project, null: false, foreign_key: true
      table.integer :state, null: false, default: 0
      table.string :client_key, limit: 64, null: false
      table.string :alt_text, limit: 1000
      table.string :media_type, limit: 40
      table.integer :width
      table.integer :height
      table.bigint :byte_size
      table.string :failure_code, limit: 64

      table.timestamps
    end

    add_index :image_attachments, %i[image_attachment_batch_id client_key],
      unique: true,
      where: "image_attachment_batch_id IS NOT NULL",
      name: "index_image_attachments_on_batch_client_key"

    add_check_constraint :image_attachments, "state IN (0, 1, 2)",
      name: "image_attachments_valid_state"
    add_check_constraint :image_attachments, PARENT_CHECK,
      name: "image_attachments_exclusive_parent"
    add_check_constraint :image_attachments, SUBMITTED_READY_CHECK,
      name: "image_attachments_submitted_ready"
    add_check_constraint :image_attachments, "byte_size IS NULL OR byte_size >= 0",
      name: "image_attachments_nonnegative_bytes"
  end
end
