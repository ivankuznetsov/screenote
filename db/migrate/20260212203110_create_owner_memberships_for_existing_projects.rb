class CreateOwnerMembershipsForExistingProjects < ActiveRecord::Migration[8.1]
  def up
    # Create owner memberships for all existing projects that don't have one yet.
    # Uses raw SQL to avoid coupling to application models.
    execute <<~SQL
      INSERT INTO project_memberships (project_id, user_id, role, created_at, updated_at)
      SELECT p.id, p.user_id, 1, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP
      FROM projects p
      WHERE NOT EXISTS (
        SELECT 1 FROM project_memberships pm
        WHERE pm.project_id = p.id AND pm.role = 1
      )
    SQL

    # Validate: every project must have exactly one owner membership
    orphan_count = execute(<<~SQL).first&.values&.first.to_i
      SELECT COUNT(*) FROM projects p
      WHERE NOT EXISTS (
        SELECT 1 FROM project_memberships pm
        WHERE pm.project_id = p.id AND pm.role = 1
      )
    SQL

    raise "Data migration failed: #{orphan_count} projects without owner membership" if orphan_count > 0
  end

  def down
    # Only remove memberships that were auto-created (owner role)
    # where no other memberships exist for the project
    execute <<~SQL
      DELETE FROM project_memberships WHERE role = 1
    SQL
  end
end
