class AddNotifiedAtToAnnotationComments < ActiveRecord::Migration[8.1]
  def change
    add_column :annotation_comments, :notified_at, :datetime

    reversible do |dir|
      dir.up do
        execute "UPDATE annotation_comments SET notified_at = CURRENT_TIMESTAMP WHERE action = 1"
      end
    end
  end
end
