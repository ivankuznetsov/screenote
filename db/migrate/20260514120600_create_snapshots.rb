# frozen_string_literal: true

class CreateSnapshots < ActiveRecord::Migration[8.1]
  def change
    create_table :snapshots do |t|
      t.references :project, null: false, foreign_key: true
      t.string :git_commit, null: false, limit: 40
      t.datetime :taken_at, null: false

      t.timestamps
    end

    # Direction-less by design: SQLite and Postgres can scan the ASC b-tree
    # backwards for `Snapshot.recent` (taken_at DESC). The id-equality path
    # used by `current_project.snapshots.find_by(id:)` is served by the PK,
    # not this composite — the composite is purely for the recent-snapshots
    # listing within a project.
    add_index :snapshots, [ :project_id, :taken_at ]
  end
end
