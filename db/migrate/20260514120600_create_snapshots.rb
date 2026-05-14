# frozen_string_literal: true

class CreateSnapshots < ActiveRecord::Migration[8.1]
  def change
    create_table :snapshots do |t|
      t.references :project, null: false, foreign_key: true
      t.string :git_commit, null: false
      t.datetime :taken_at, null: false

      t.timestamps
    end

    add_index :snapshots, [ :project_id, :taken_at ]
  end
end
