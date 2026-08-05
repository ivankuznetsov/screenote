# frozen_string_literal: true

class AddApiKeyIssuersAndAnnotationActors < ActiveRecord::Migration[8.1]
  ACTOR_CONSTRAINT = <<~SQL.squish.freeze
    (user_id IS NOT NULL AND api_key_id IS NULL) OR
    (user_id IS NULL AND api_key_id IS NOT NULL)
  SQL
  RESOLUTION_CONSTRAINT = <<~SQL.squish.freeze
    (status = 0 AND resolved_by_user_id IS NULL AND resolved_by_api_key_id IS NULL) OR
    (status = 1 AND (
      (resolved_by_user_id IS NOT NULL AND resolved_by_api_key_id IS NULL) OR
      (resolved_by_user_id IS NULL AND resolved_by_api_key_id IS NOT NULL)
    ))
  SQL
  ACTIVE_ISSUER_CONSTRAINT = <<~SQL.squish.freeze
    revoked_at IS NOT NULL OR issued_by_user_id IS NOT NULL
  SQL

  def up
    lock_actor_tables
    preflight_legacy_rows!
    actor_invariants = legacy_actor_invariants
    annotation_comments_detached = detach_annotation_comments_for_sqlite_rebuild
    detach_api_key_children_for_sqlite_rebuild

    add_reference :api_keys, :issued_by_user,
      foreign_key: { to_table: :users }, index: true
    # The legacy schema cannot prove who issued an existing key. Revoke those
    # credentials without fabricating provenance, while retaining actor rows.
    execute <<~SQL.squish
      UPDATE #{quoted_table(:api_keys)}
      SET revoked_at = CURRENT_TIMESTAMP
      WHERE revoked_at IS NULL
    SQL
    add_check_constraint :api_keys, ACTIVE_ISSUER_CONSTRAINT,
      name: "api_keys_active_requires_issuer"

    add_reference :annotations, :api_key, foreign_key: true, index: true
    change_column_null :annotations, :user_id, true

    preserve_actor_foreign_keys

    add_check_constraint :annotations, ACTOR_CONSTRAINT,
      name: "annotations_exactly_one_actor"
    add_check_constraint :annotations, RESOLUTION_CONSTRAINT,
      name: "annotations_resolution_actor_state"
    add_check_constraint :annotation_comments, ACTOR_CONSTRAINT,
      name: "annotation_comments_exactly_one_actor"
    restore_annotation_comments_foreign_key if annotation_comments_detached
    verify_legacy_actor_invariants!(actor_invariants)
  end

  def down
    raise ActiveRecord::IrreversibleMigration,
      "Legacy key revocation and immutable actor provenance cannot be safely reversed"
  end

  private

  def lock_actor_tables
    return unless connection.adapter_name == "PostgreSQL"

    connection.execute("SET LOCAL lock_timeout = '10s'")
    tables = %i[users api_keys annotations annotation_comments]
      .map { |table| quoted_table(table) }
      .join(", ")
    connection.execute("LOCK TABLE #{tables} IN ACCESS EXCLUSIVE MODE")
  end

  def preflight_legacy_rows!
    problems = {
      "annotations actor" => invalid_ids(<<~SQL),
        SELECT annotations.id
        FROM #{quoted_table(:annotations)} annotations
        WHERE annotations.user_id IS NULL
      SQL
      "annotations resolution" => invalid_ids(<<~SQL),
        SELECT annotations.id
        FROM #{quoted_table(:annotations)} annotations
        WHERE NOT (
          (annotations.status = 0 AND
            annotations.resolved_by_user_id IS NULL AND
            annotations.resolved_by_api_key_id IS NULL) OR
          (annotations.status = 1 AND (
            (annotations.resolved_by_user_id IS NOT NULL AND annotations.resolved_by_api_key_id IS NULL) OR
            (annotations.resolved_by_user_id IS NULL AND annotations.resolved_by_api_key_id IS NOT NULL)
          ))
        )
      SQL
      "annotation_comments actor" => invalid_ids(<<~SQL)
        SELECT annotation_comments.id
        FROM #{quoted_table(:annotation_comments)} annotation_comments
        WHERE (annotation_comments.user_id IS NULL AND annotation_comments.api_key_id IS NULL)
           OR (annotation_comments.user_id IS NOT NULL AND annotation_comments.api_key_id IS NOT NULL)
      SQL
    }.reject { |_label, ids| ids.empty? }
    return if problems.empty?

    details = problems.map { |label, ids| "#{label} IDs: #{ids.join(', ')}" }.join("; ")
    raise ActiveRecord::MigrationError,
      "Cannot add principal provenance until invalid legacy rows are repaired: #{details}"
  end

  def invalid_ids(sql)
    connection.select_values(<<~SQL.squish).map(&:to_i)
      SELECT invalid_rows.id
      FROM (#{sql.squish}) invalid_rows
      ORDER BY invalid_rows.id
      LIMIT 100
    SQL
  end

  def preserve_actor_foreign_keys
    replace_nullifying_foreign_key(:annotations, :users, :resolved_by_user_id)
    replace_nullifying_foreign_key(:annotations, :api_keys, :resolved_by_api_key_id)
    replace_nullifying_foreign_key(:annotation_comments, :users, :user_id)
    replace_nullifying_foreign_key(:annotation_comments, :api_keys, :api_key_id)
  end

  def detach_annotation_comments_for_sqlite_rebuild
    return false unless connection.adapter_name == "SQLite"
    return false unless foreign_key_exists?(:annotation_comments, :annotations, column: :annotation_id)

    remove_foreign_key :annotation_comments, column: :annotation_id
    true
  end

  def detach_api_key_children_for_sqlite_rebuild
    return unless connection.adapter_name == "SQLite"

    if foreign_key_exists?(:annotations, :api_keys, column: :resolved_by_api_key_id)
      remove_foreign_key :annotations, column: :resolved_by_api_key_id
    end
    if foreign_key_exists?(:annotation_comments, :api_keys, column: :api_key_id)
      remove_foreign_key :annotation_comments, column: :api_key_id
    end
  end

  def restore_annotation_comments_foreign_key
    add_foreign_key :annotation_comments, :annotations, column: :annotation_id, on_delete: :cascade
  end

  def legacy_actor_invariants
    {
      annotations: row_count(:annotations),
      annotation_comments: row_count(:annotation_comments),
      api_key_resolutions: non_null_count(:annotations, :resolved_by_api_key_id),
      api_key_comments: non_null_count(:annotation_comments, :api_key_id)
    }
  end

  def verify_legacy_actor_invariants!(expected)
    actual = legacy_actor_invariants
    return if actual == expected

    raise ActiveRecord::MigrationError,
      "Actor migration changed legacy row or API-key attribution counts: expected #{expected.inspect}, got #{actual.inspect}"
  end

  def row_count(table)
    connection.select_value("SELECT COUNT(*) FROM #{quoted_table(table)}").to_i
  end

  def non_null_count(table, column)
    quoted_column = connection.quote_column_name(column)
    connection.select_value(<<~SQL.squish).to_i
      SELECT COUNT(*) FROM #{quoted_table(table)} WHERE #{quoted_column} IS NOT NULL
    SQL
  end

  def replace_nullifying_foreign_key(from_table, to_table, column)
    remove_foreign_key from_table, column: column if foreign_key_exists?(from_table, column: column)
    add_foreign_key from_table, to_table, column: column
  end

  def quoted_table(table)
    connection.quote_table_name(table)
  end
end
