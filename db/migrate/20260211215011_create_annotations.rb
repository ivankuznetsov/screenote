# frozen_string_literal: true

class CreateAnnotations < ActiveRecord::Migration[8.1]
  def change
    create_table :annotations do |t|
      t.references :screenshot, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true
      t.float :x_percent, null: false
      t.float :y_percent, null: false
      t.float :width_percent
      t.float :height_percent
      t.text :comment
      t.integer :status, default: 0, null: false
      t.references :resolved_by_user, foreign_key: { to_table: :users }
      t.references :resolved_by_api_key

      t.timestamps
    end

    add_index :annotations, %i[screenshot_id status]
  end
end
