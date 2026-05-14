# frozen_string_literal: true

class CreateSnapshots < ActiveRecord::Migration[8.1]
  def change
    create_table :snapshots do |t|
      t.references :project, null: false, foreign_key: true
      t.string :git_commit, null: false
      t.datetime :taken_at, null: false

      t.timestamps
    end

    # Direction-less by design: SQLite and Postgres can scan the ASC b-tree
    # backwards for `Snapshot.recent` (taken_at DESC) and forwards for the
    # `current_project.snapshots.find_by(id:)` access path used by
    # CreateMultiViewportScreenshotTool. Splitting into two indexes would
    # double write cost for no measurable read benefit at our scale.
    add_index :snapshots, [ :project_id, :taken_at ]
  end
end
