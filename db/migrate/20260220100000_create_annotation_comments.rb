# frozen_string_literal: true

class CreateAnnotationComments < ActiveRecord::Migration[8.1]
  def change
    create_table :annotation_comments do |t|
      t.references :annotation, null: false, foreign_key: false
      t.references :user, null: true, foreign_key: false
      t.references :api_key, null: true, foreign_key: false
      t.text :body, null: false
      t.integer :action, null: false, default: 0

      t.timestamps
    end

    add_index :annotation_comments, [ :annotation_id, :created_at ]

    add_foreign_key :annotation_comments, :annotations, on_delete: :cascade
    add_foreign_key :annotation_comments, :users, on_delete: :nullify
    add_foreign_key :annotation_comments, :api_keys, on_delete: :nullify
  end
end
