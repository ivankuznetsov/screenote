class CreateProjectInvitations < ActiveRecord::Migration[8.1]
  def change
    create_table :project_invitations do |t|
      t.references :project, null: false, foreign_key: true
      t.references :inviter, null: false, foreign_key: { to_table: :users }
      t.string :email, null: false
      t.integer :status, null: false, default: 0

      t.timestamps
    end

    add_index :project_invitations, [ :project_id, :email ], unique: true
  end
end
