# frozen_string_literal: true

class CreateAnnotationComments < ActiveRecord::Migration[8.1]
  def change
    create_table :annotation_comments do |t|
      t.references :annotation, null: false, foreign_key: true
      t.references :user, null: true, foreign_key: true
      t.references :api_key, null: true, foreign_key: true
      t.text :body, null: false
      t.integer :action, null: false, default: 0

      t.timestamps
    end

    add_index :annotation_comments, [ :annotation_id, :created_at ]
  end
end
