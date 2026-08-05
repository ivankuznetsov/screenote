# frozen_string_literal: true

require "digest"

class HardenOauthPrincipalsAndTokenSecrets < ActiveRecord::Migration[8.1]
  PRINCIPAL_CHECK = <<~SQL.squish.freeze
    (principal_kind = 'user' AND project_id IS NULL) OR
    (principal_kind = 'project' AND project_id IS NOT NULL)
  SQL

  DEVICE_PRINCIPAL_CHECK = <<~SQL.squish.freeze
    (approved_at IS NULL AND principal_kind IS NULL AND project_id IS NULL) OR
    (approved_at IS NOT NULL AND resource_owner_id IS NOT NULL AND (
      (principal_kind = 'user' AND project_id IS NULL) OR
      (principal_kind = 'project' AND project_id IS NOT NULL)
    ))
  SQL

  def up
    bound_postgresql_lock_wait
    preflight_legacy_rows!

    add_column :oauth_access_grants, :principal_kind, :string
    add_column :oauth_access_tokens, :principal_kind, :string
    add_column :oauth_device_grants, :principal_kind, :string
    add_reference :oauth_device_grants, :project, index: true
    add_column :oauth_applications, :registration_fingerprint, :string, limit: 64
    add_column :oauth_applications, :last_used_at, :datetime

    backfill_principals!
    backfill_dynamic_registration_fingerprints!
    hash_stored_secrets!

    change_column_null :oauth_access_grants, :principal_kind, false
    change_column_null :oauth_access_tokens, :principal_kind, false
    change_column_null :oauth_access_tokens, :resource_owner_id, false

    add_check_constraint :oauth_access_grants, PRINCIPAL_CHECK,
      name: "oauth_access_grants_valid_principal"
    add_check_constraint :oauth_access_tokens, PRINCIPAL_CHECK,
      name: "oauth_access_tokens_valid_principal"
    add_check_constraint :oauth_device_grants, DEVICE_PRINCIPAL_CHECK,
      name: "oauth_device_grants_valid_principal"
    add_check_constraint :oauth_device_grants,
      "approved_at IS NULL OR denied_at IS NULL",
      name: "oauth_device_grants_single_terminal_decision"

    add_secret_constraints!
    replace_project_foreign_keys!

    add_index :oauth_applications, :registration_fingerprint,
      unique: true,
      where: "dynamic = TRUE AND registration_fingerprint IS NOT NULL",
      name: "index_dynamic_oauth_apps_on_registration_fingerprint"
  end

  def down
    raise ActiveRecord::IrreversibleMigration,
      "OAuth principal provenance and plaintext bearer secrets cannot be safely restored"
  end

  private

  def bound_postgresql_lock_wait
    execute("SET LOCAL lock_timeout = '10s'") if connection.adapter_name == "PostgreSQL"
  end

  def preflight_legacy_rows!
    invalid_tokens = select_ids(<<~SQL.squish)
      SELECT id FROM oauth_access_tokens
      WHERE resource_owner_id IS NULL
      ORDER BY id
    SQL
    invalid_device_grants = select_ids(<<~SQL.squish)
      SELECT id FROM oauth_device_grants
      WHERE (approved_at IS NOT NULL AND resource_owner_id IS NULL)
         OR (approved_at IS NOT NULL AND denied_at IS NOT NULL)
      ORDER BY id
    SQL

    problems = []
    problems << "oauth_access_tokens missing resource owner IDs: #{invalid_tokens.join(', ')}" if invalid_tokens.any?
    problems << "oauth_device_grants with invalid approval state: #{invalid_device_grants.join(', ')}" if invalid_device_grants.any?

    return if problems.empty?

    raise ActiveRecord::MigrationError, "OAuth principal preflight failed: #{problems.join('; ')}"
  end

  def backfill_principals!
    execute <<~SQL.squish
      UPDATE oauth_access_grants
      SET principal_kind = CASE WHEN project_id IS NULL THEN 'user' ELSE 'project' END
    SQL
    execute <<~SQL.squish
      UPDATE oauth_access_tokens
      SET principal_kind = CASE WHEN project_id IS NULL THEN 'user' ELSE 'project' END
    SQL
    execute <<~SQL.squish
      UPDATE oauth_device_grants
      SET principal_kind = 'user'
      WHERE approved_at IS NOT NULL
    SQL
  end

  def backfill_dynamic_registration_fingerprints!
    # Dynamic registration was historically non-idempotent, so installations
    # can legitimately contain duplicate clients. Preserve every credential,
    # but make the oldest row canonical for future idempotent registrations.
    rows_by_fingerprint = dynamic_application_rows.group_by do |_id, name, redirect_uri|
      registration_fingerprint(name, redirect_uri)
    end
    rows_by_fingerprint.each do |fingerprint, rows|
      id = rows.first.first
      execute <<~SQL.squish
        UPDATE oauth_applications
        SET registration_fingerprint = #{quote(fingerprint)}
        WHERE id = #{quote(id)}
      SQL
    end
  end

  def hash_stored_secrets!
    hash_column(:oauth_access_grants, :token)
    hash_column(:oauth_access_tokens, :token)
    hash_column(:oauth_access_tokens, :refresh_token, allow_null: true)
    hash_column(:oauth_access_tokens, :previous_refresh_token, allow_blank: true)
    hash_column(:oauth_applications, :secret, allow_null: true)
  end

  def hash_column(table, column, allow_null: false, allow_blank: false)
    quoted_table = connection.quote_table_name(table)
    quoted_column = connection.quote_column_name(column)
    conditions = []
    conditions << "#{quoted_column} IS NOT NULL" if allow_null
    conditions << "#{quoted_column} <> ''" if allow_blank
    where = conditions.any? ? " WHERE #{conditions.join(' AND ')}" : ""

    connection.select_rows("SELECT id, #{quoted_column} FROM #{quoted_table}#{where}").each do |id, plaintext|
      next if plaintext.nil? || (allow_blank && plaintext.empty?)

      digest = Digest::SHA256.hexdigest(plaintext)
      execute <<~SQL.squish
        UPDATE #{quoted_table}
        SET #{quoted_column} = #{quote(digest)}
        WHERE id = #{quote(id)}
      SQL
    end
  end

  def add_secret_constraints!
    add_check_constraint :oauth_access_grants, "length(token) = 64",
      name: "oauth_access_grants_hashed_token"
    add_check_constraint :oauth_access_tokens, "length(token) = 64",
      name: "oauth_access_tokens_hashed_token"
    add_check_constraint :oauth_access_tokens,
      "refresh_token IS NULL OR length(refresh_token) = 64",
      name: "oauth_access_tokens_hashed_refresh_token"
    add_check_constraint :oauth_access_tokens,
      "previous_refresh_token = '' OR length(previous_refresh_token) = 64",
      name: "oauth_access_tokens_hashed_previous_refresh_token"
    # Do not rebuild oauth_applications to add SQLite CHECK constraints here:
    # it is the parent of grants, tokens, and device grants, and SQLite can
    # cascade-delete those children while replacing the parent table. Runtime
    # secret storage and the fixed-width fingerprint writer enforce these two
    # application fields without risking credential loss during upgrade.
  end

  def replace_project_foreign_keys!
    remove_foreign_key :oauth_access_grants, :projects, column: :project_id
    remove_foreign_key :oauth_access_tokens, :projects, column: :project_id

    add_foreign_key :oauth_access_grants, :projects, column: :project_id, on_delete: :cascade
    add_foreign_key :oauth_access_tokens, :projects, column: :project_id, on_delete: :cascade
    add_foreign_key :oauth_device_grants, :projects, column: :project_id, on_delete: :cascade
  end

  def dynamic_application_rows
    connection.select_rows(<<~SQL.squish)
      SELECT id, name, redirect_uri
      FROM oauth_applications
      WHERE dynamic = TRUE
      ORDER BY id
    SQL
  end

  def registration_fingerprint(name, redirect_uri)
    normalized_redirects = redirect_uri.to_s.split("\n").sort.join("\n")
    Digest::SHA256.hexdigest([ name.to_s, normalized_redirects ].join("\0"))
  end

  def select_ids(sql)
    connection.select_values(sql).map(&:to_i)
  end

  def quote(value)
    connection.quote(value)
  end
end
