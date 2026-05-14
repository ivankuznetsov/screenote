class FixProjectInvitationsIndex < ActiveRecord::Migration[8.1]
  def change
    remove_index :project_invitations, [:project_id, :email], name: "index_project_invitations_on_project_id_and_email"
    add_index :project_invitations, [:project_id, :email, :status]
  end
end
