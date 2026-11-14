# frozen_string_literal: true

class ReplaceRedundantIndexesAndRequireAnnotationComment < ActiveRecord::Migration[8.1]
  # Each of these single-column indexes is the leading column of a composite
  # index on the same table (noted alongside), which serves the same lookups,
  # foreign-key checks included. The single-column copy only costs writes.
  PREFIX_INDEXES = {
    annotations: :screenshot_id,             # (screenshot_id, status), (screenshot_id, viewport)
    annotation_comments: :annotation_id,     # (annotation_id, created_at)
    image_attachment_batches: :user_id,      # (user_id, state)
    project_memberships: :project_id,        # (project_id, user_id), unique
    screenshot_images: :screenshot_id,       # (screenshot_id, viewport), unique
    snapshots: :project_id,                  # (project_id, taken_at)
    pages: :project_id,                      # (project_id, LOWER(name)), unique
    screenshots: :page_id                    # (page_id, created_at), added below
  }.freeze

  # Left over from screenshots.project_id: SQLite kept the created_at half when
  # that column was dropped, while other adapters drop the whole index, so it
  # may or may not exist. Pages list their screenshots newest first, so the
  # useful index leads with page_id.
  LEGACY_SCREENSHOTS_INDEX = "index_screenshots_on_project_id_and_created_at"

  def up
    add_index :screenshots, %i[page_id created_at], if_not_exists: true
    remove_index :screenshots, name: LEGACY_SCREENSHOTS_INDEX, if_exists: true
    PREFIX_INDEXES.each do |table, column|
      remove_index table, column, name: "index_#{table}_on_#{column}", if_exists: true
    end

    require_annotation_comment
  end

  def down
    rebuilding_annotations { change_column_null :annotations, :comment, true }

    PREFIX_INDEXES.each do |table, column|
      add_index table, column, name: "index_#{table}_on_#{column}", if_not_exists: true
    end
    add_index :screenshots, :created_at, name: LEGACY_SCREENSHOTS_INDEX, if_not_exists: true
    remove_index :screenshots, %i[page_id created_at], if_exists: true
  end

  private

  # Annotation has validated comment presence since 2026-02-12, the day the
  # table was introduced, and nothing writes annotations around validations,
  # so no NULL comment is expected. Should one exist, stop with the offending
  # IDs instead of inventing text: a blank comment would still fail the model's
  # presence validation the next time the annotation is resolved or reopened.
  def require_annotation_comment
    null_ids = select_values(<<~SQL.squish)
      SELECT id FROM #{quote_table_name(:annotations)} WHERE comment IS NULL ORDER BY id LIMIT 100
    SQL
    if null_ids.any?
      raise ActiveRecord::MigrationError,
        "annotations.comment must be present before it can be NOT NULL; repair annotation IDs: #{null_ids.join(', ')}"
    end

    rebuilding_annotations { change_column_null :annotations, :comment, false }
  end

  # SQLite changes nullability by rebuilding the table. Foreign keys stay
  # enforced inside the migration transaction, so dropping the old annotations
  # table would fire annotation_comments' ON DELETE CASCADE and delete every
  # comment. Detach that key for the rebuild, as 20260805130000 does.
  def rebuilding_annotations
    detached = connection.adapter_name == "SQLite" &&
      foreign_key_exists?(:annotation_comments, :annotations, column: :annotation_id)
    remove_foreign_key :annotation_comments, :annotations, column: :annotation_id if detached

    yield

    add_foreign_key :annotation_comments, :annotations, column: :annotation_id, on_delete: :cascade if detached
  end
end
