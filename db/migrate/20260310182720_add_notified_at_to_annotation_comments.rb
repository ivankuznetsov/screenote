class AddNotifiedAtToAnnotationComments < ActiveRecord::Migration[8.1]
  def up
    add_column :annotation_comments, :notified_at, :datetime

    add_index :annotation_comments, [ :action, :notified_at ],
              name: "index_annotation_comments_on_action_notified_at"

    # action enum: { comment: 0, resolved: 1, reopened: 2 }
    execute "UPDATE annotation_comments SET notified_at = CURRENT_TIMESTAMP WHERE action = 1"
  end

  def down
    remove_column :annotation_comments, :notified_at
  end
end
