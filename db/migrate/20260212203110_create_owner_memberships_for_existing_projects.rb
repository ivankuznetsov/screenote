class CreateOwnerMembershipsForExistingProjects < ActiveRecord::Migration[8.1]
  def up
    # Create owner memberships for all existing projects that don't have one yet.
    # Uses raw SQL to avoid coupling to application models.
    # Guards against projects with NULL user_id.
    execute <<~SQL
      INSERT INTO project_memberships (project_id, user_id, role, created_at, updated_at)
      SELECT p.id, p.user_id, 1, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP
      FROM projects p
      WHERE p.user_id IS NOT NULL
        AND NOT EXISTS (
          SELECT 1 FROM project_memberships pm
          WHERE pm.project_id = p.id AND pm.role = 1
        )
    SQL

    # Validate: every project with a creator must have an owner membership
    result = execute(<<~SQL)
      SELECT COUNT(*) AS orphan_count FROM projects p
      WHERE p.user_id IS NOT NULL
        AND NOT EXISTS (
          SELECT 1 FROM project_memberships pm
          WHERE pm.project_id = p.id AND pm.role = 1
        )
    SQL

    orphan_count = result.first["orphan_count"].to_i
    raise "Data migration failed: #{orphan_count} projects without owner membership" if orphan_count > 0
  end

  def down
    raise ActiveRecord::IrreversibleMigration,
      "Cannot safely reverse owner membership creation. Manually remove memberships if needed."
  end
end
