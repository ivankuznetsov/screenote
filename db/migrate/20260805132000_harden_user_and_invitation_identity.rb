# frozen_string_literal: true

class HardenUserAndInvitationIdentity < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  USER_EMAIL_CHECK = "email <> '' AND email = LOWER(TRIM(email))"
  USER_OAUTH_CHECK = <<~SQL.squish.freeze
    (oauth_provider IS NULL AND oauth_uid IS NULL) OR
    (oauth_provider IS NOT NULL AND oauth_uid IS NOT NULL AND
      oauth_provider <> '' AND oauth_uid <> '' AND
      oauth_provider = LOWER(TRIM(oauth_provider)) AND
      oauth_uid = TRIM(oauth_uid))
  SQL
  INVITATION_EMAIL_CHECK = "email <> '' AND email = LOWER(TRIM(email))"
  PRESERVED_TABLES = %w[
    users sessions projects project_memberships project_invitations subscriptions
    annotations annotation_comments api_keys oauth_access_grants oauth_access_tokens
    oauth_device_grants installations
  ].freeze
  NEW_INDEXES = {
    users: %w[index_users_on_normalized_email index_users_on_oauth_identity],
    project_invitations: %w[index_project_invitations_on_pending_normalized_email],
    installation_audit_events: %w[
      index_installation_audit_events_on_installation_id
      index_installation_audit_events_on_actor_user_id
      index_installation_audit_events_on_target_user_id
    ]
  }.freeze
  NEW_CONSTRAINTS = {
    users: %w[users_normalized_email users_valid_access_status users_valid_oauth_identity],
    project_invitations: %w[project_invitations_normalized_email project_invitations_valid_status],
    installation_audit_events: %w[installation_audit_events_normalized_type]
  }.freeze
  LEGACY_INDEXES = {
    users: "index_users_on_email",
    project_invitations: "index_project_invitations_on_project_id_and_email_and_status"
  }.freeze

  def up
    case migration_state
    when :legacy
      sqlite? ? migrate_sqlite! : migrate_transactionally!
    when :complete
      verify_completed_identity_data!
    else
      raise ActiveRecord::MigrationError,
        "Identity migration found a partially applied schema; restore the pre-migration backup before retrying"
    end
  end

  def down
    raise ActiveRecord::IrreversibleMigration,
      "Canonical identity data and durable invitation states cannot be safely restored"
  end

  private

  def migration_state
    return :complete if completed_schema?
    return :legacy if legacy_schema?

    :partial
  end

  def completed_schema?
    access_status = connection.columns(:users).find { |column| column.name == "access_status" }
    return false unless access_status&.type == :integer && !access_status.null && access_status.default.to_s == "0"
    return false unless connection.table_exists?(:installation_audit_events)
    return false unless LEGACY_INDEXES.none? { |table, name| index_names(table).include?(name) }
    return false unless NEW_INDEXES.all? { |table, names| (names - index_names(table)).empty? }
    return false unless NEW_CONSTRAINTS.all? { |table, names| (names - constraint_names(table)).empty? }
    return false unless installation_audit_event_shape_complete?

    true
  end

  def legacy_schema?
    return false if connection.column_exists?(:users, :access_status)
    return false if connection.table_exists?(:installation_audit_events)
    return false unless LEGACY_INDEXES.all? { |table, name| index_names(table).include?(name) }

    NEW_INDEXES.all? { |table, names| (names & index_names(table)).empty? } &&
      NEW_CONSTRAINTS.all? { |table, names| (names & constraint_names(table)).empty? }
  end

  def installation_audit_event_shape_complete?
    columns = connection.columns(:installation_audit_events).index_by(&:name)
    required_nullability = {
      "installation_id" => false,
      "actor_user_id" => true,
      "target_user_id" => true,
      "event_type" => false,
      "metadata" => false,
      "created_at" => false
    }
    return false unless required_nullability.all? do |name, nullable|
      columns[name]&.null == nullable
    end

    foreign_key_columns = connection.foreign_keys(:installation_audit_events).map(&:column)
    %w[installation_id actor_user_id target_user_id].all? { |column| foreign_key_columns.include?(column) }
  end

  def verify_completed_identity_data!
    invalid_users = connection.select_value(<<~SQL.squish).to_i
      SELECT COUNT(*)
      FROM #{quoted_table(:users)}
      WHERE email = ''
         OR email <> LOWER(TRIM(email))
         OR access_status NOT IN (0, 1)
         OR NOT (
           (oauth_provider IS NULL AND oauth_uid IS NULL) OR
           (oauth_provider IS NOT NULL AND oauth_uid IS NOT NULL AND
             oauth_provider <> '' AND oauth_uid <> '' AND
             oauth_provider = LOWER(TRIM(oauth_provider)) AND
             oauth_uid = TRIM(oauth_uid))
         )
    SQL
    invalid_invitations = connection.select_value(<<~SQL.squish).to_i
      SELECT COUNT(*)
      FROM #{quoted_table(:project_invitations)}
      WHERE email = ''
         OR email <> LOWER(TRIM(email))
         OR status NOT IN (0, 1, 2)
    SQL
    return if invalid_users.zero? && invalid_invitations.zero?

    raise ActiveRecord::MigrationError,
      "Identity migration re-entry found data outside the completed constraints"
  end

  def index_names(table)
    return [] unless connection.table_exists?(table)

    connection.indexes(table).map(&:name)
  end

  def constraint_names(table)
    return [] unless connection.table_exists?(table)

    connection.check_constraints(table).map(&:name)
  end

  def migrate_sqlite!
    # SQLite rebuilds a table when Rails adds a CHECK constraint. `users` is a
    # parent of most of the application graph, so foreign-key enforcement must
    # be disabled before (not inside) the explicit transaction. Otherwise
    # dropping the old table can cascade-delete valid child rows.
    foreign_keys_enabled = connection.select_value("PRAGMA foreign_keys").to_i == 1
    connection.execute("PRAGMA foreign_keys = OFF")

    connection.transaction do
      before = preservation_snapshot
      preflight_identity!
      migrate_schema!
      verify_preservation!(before)
      verify_sqlite_foreign_keys!
    end

    connection.execute("PRAGMA foreign_keys = ON") if foreign_keys_enabled
    verify_sqlite_foreign_keys!
  ensure
    connection.execute("PRAGMA foreign_keys = ON") if foreign_keys_enabled
  end

  def migrate_transactionally!
    connection.transaction do
      bound_postgresql_lock_wait
      lock_identity_tables
      before = preservation_snapshot
      preflight_identity!
      migrate_schema!
      verify_preservation!(before)
    end
  end

  def migrate_schema!
    canonicalize_identities!
    add_access_status!
    replace_identity_indexes!
    add_identity_constraints!
    create_installation_audit_events!
  end

  def preflight_identity!
    user_rows = connection.select_rows(<<~SQL.squish)
      SELECT id, email, oauth_provider, oauth_uid
      FROM #{quoted_table(:users)}
      ORDER BY id
    SQL
    invitation_rows = connection.select_rows(<<~SQL.squish)
      SELECT id, project_id, email, status
      FROM #{quoted_table(:project_invitations)}
      ORDER BY id
    SQL

    duplicate_emails = duplicate_groups(user_rows) { |_id, email, _provider, _uid| normalize(email) }
    blank_email_ids = user_rows.filter_map do |id, email, _provider, _uid|
      id.to_i if normalize(email).empty?
    end
    half_oauth_ids = user_rows.filter_map do |id, _email, provider, uid|
      id.to_i if provider.nil? ^ uid.nil?
    end
    invalid_oauth_ids = user_rows.filter_map do |id, _email, provider, uid|
      next if provider.nil? && uid.nil?

      id.to_i if normalize(provider).empty? || uid.to_s.strip.empty?
    end
    duplicate_oauth = duplicate_groups(user_rows.filter { |_id, _email, provider, uid| provider && uid }) do
      |_id, _email, provider, uid|
      [ normalize(provider), uid.to_s.strip ]
    end
    duplicate_pending = duplicate_groups(invitation_rows.filter { |_id, _project_id, _email, status| status.to_i.zero? }) do
      |_id, project_id, email, _status|
      [ project_id.to_i, normalize(email) ]
    end
    blank_invitation_ids = invitation_rows.filter_map do |id, _project_id, email, _status|
      id.to_i if normalize(email).empty?
    end
    invalid_invitation_status_ids = invitation_rows.filter_map do |id, _project_id, _email, status|
      id.to_i unless [ 0, 1 ].include?(status.to_i)
    end

    problems = []
    append_groups(problems, "duplicate normalized user emails", duplicate_emails)
    problems << "blank normalized user email IDs: #{blank_email_ids.join(', ')}" if blank_email_ids.any?
    problems << "half-populated OAuth identity user IDs: #{half_oauth_ids.join(', ')}" if half_oauth_ids.any?
    problems << "blank OAuth identity user IDs: #{invalid_oauth_ids.join(', ')}" if invalid_oauth_ids.any?
    append_groups(problems, "duplicate OAuth identities", duplicate_oauth)
    append_groups(problems, "duplicate normalized pending invitations", duplicate_pending)
    problems << "blank normalized invitation email IDs: #{blank_invitation_ids.join(', ')}" if blank_invitation_ids.any?
    if invalid_invitation_status_ids.any?
      problems << "invalid invitation status IDs: #{invalid_invitation_status_ids.join(', ')}"
    end
    return if problems.empty?

    raise ActiveRecord::MigrationError,
      "Identity preflight failed before mutation: #{problems.join('; ')}"
  end

  def duplicate_groups(rows)
    rows.group_by { |row| yield(*row) }
      .values
      .select { |group| group.length > 1 }
      .map { |group| group.map { |row| row.first.to_i }.sort }
      .sort_by(&:first)
  end

  def append_groups(problems, label, groups)
    return if groups.empty?

    problems << "#{label} (record IDs): #{groups.map { |ids| ids.join(',') }.join(' | ')}"
  end

  def canonicalize_identities!
    execute <<~SQL.squish
      UPDATE #{quoted_table(:users)}
      SET email = LOWER(TRIM(email)),
          oauth_provider = CASE
            WHEN oauth_provider IS NULL THEN NULL
            ELSE LOWER(TRIM(oauth_provider))
          END,
          oauth_uid = CASE
            WHEN oauth_uid IS NULL THEN NULL
            ELSE TRIM(oauth_uid)
          END
    SQL
    execute <<~SQL.squish
      UPDATE #{quoted_table(:project_invitations)}
      SET email = LOWER(TRIM(email))
    SQL
  end

  def add_access_status!
    add_column :users, :access_status, :integer, null: false, default: 0
  end

  def replace_identity_indexes!
    remove_index :users, :email if index_exists?(:users, :email)
    add_index :users, "LOWER(TRIM(email))",
      unique: true,
      name: "index_users_on_normalized_email"
    add_index :users, %i[oauth_provider oauth_uid],
      unique: true,
      where: "oauth_provider IS NOT NULL AND oauth_uid IS NOT NULL",
      name: "index_users_on_oauth_identity"

    remove_index :project_invitations,
      name: "index_project_invitations_on_project_id_and_email_and_status",
      if_exists: true
    add_index :project_invitations, "project_id, LOWER(TRIM(email))",
      unique: true,
      where: "status = 0",
      name: "index_project_invitations_on_pending_normalized_email"
  end

  def add_identity_constraints!
    add_check_constraint :users, USER_EMAIL_CHECK,
      name: "users_normalized_email"
    add_check_constraint :users, "access_status IN (0, 1)",
      name: "users_valid_access_status"
    add_check_constraint :users, USER_OAUTH_CHECK,
      name: "users_valid_oauth_identity"

    add_check_constraint :project_invitations, INVITATION_EMAIL_CHECK,
      name: "project_invitations_normalized_email"
    add_check_constraint :project_invitations, "status IN (0, 1, 2)",
      name: "project_invitations_valid_status"
  end

  def create_installation_audit_events!
    create_table :installation_audit_events do |table|
      table.references :installation, null: false, foreign_key: true
      table.references :actor_user, foreign_key: { to_table: :users }
      table.references :target_user, foreign_key: { to_table: :users }
      table.string :event_type, null: false
      table.json :metadata, null: false, default: {}
      table.datetime :created_at, null: false
    end

    add_check_constraint :installation_audit_events,
      "event_type <> '' AND event_type = LOWER(TRIM(event_type))",
      name: "installation_audit_events_normalized_type"
  end

  def preservation_snapshot
    PRESERVED_TABLES
      .select { |table| connection.table_exists?(table) }
      .to_h { |table| [ table, row_identity(table) ] }
  end

  def row_identity(table)
    quoted = connection.quote_table_name(table)
    if connection.column_exists?(table, :id)
      connection.select_values("SELECT id FROM #{quoted} ORDER BY id").map(&:to_s)
    else
      [ connection.select_value("SELECT COUNT(*) FROM #{quoted}").to_i ]
    end
  end

  def verify_preservation!(before)
    changed = before.filter_map do |table, identity|
      next unless connection.table_exists?(table)
      next if row_identity(table) == identity

      table
    end
    return if changed.empty?

    raise ActiveRecord::MigrationError,
      "Identity migration changed existing row IDs in: #{changed.join(', ')}"
  end

  def verify_sqlite_foreign_keys!
    violations = connection.select_rows("PRAGMA foreign_key_check")
    return if violations.empty?

    details = violations.first(100).map { |row| row.join(":") }.join(", ")
    raise ActiveRecord::MigrationError,
      "Identity migration left SQLite foreign-key violations: #{details}"
  end

  def bound_postgresql_lock_wait
    execute("SET LOCAL lock_timeout = '10s'") if postgresql?
  end

  def lock_identity_tables
    return unless postgresql?

    tables = PRESERVED_TABLES
      .select { |table| connection.table_exists?(table) }
      .map { |table| quoted_table(table) }
      .join(", ")
    execute "LOCK TABLE #{tables} IN ACCESS EXCLUSIVE MODE"
  end

  def normalize(value)
    value.to_s.strip.downcase
  end

  def quoted_table(table)
    connection.quote_table_name(table)
  end

  def sqlite?
    connection.adapter_name == "SQLite"
  end

  def postgresql?
    connection.adapter_name == "PostgreSQL"
  end
end
