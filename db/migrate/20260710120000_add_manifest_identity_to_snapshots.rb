# frozen_string_literal: true

class AddManifestIdentityToSnapshots < ActiveRecord::Migration[8.1]
  def change
    add_column :snapshots, :manifest_digest, :string, limit: 64
    add_column :screenshots, :manifest_entry_digest, :string, limit: 64
    add_column :screenshot_images, :content_sha256, :string, limit: 64

    add_index :snapshots, [ :project_id, :manifest_digest ],
      unique: true,
      where: "manifest_digest IS NOT NULL",
      name: "idx_snapshots_project_manifest_digest"
    add_index :screenshots, [ :snapshot_id, :manifest_entry_digest ],
      unique: true,
      where: "manifest_entry_digest IS NOT NULL",
      name: "idx_screenshots_snapshot_entry_digest"
  end
end
