# frozen_string_literal: true

class CreateScreenshots < ActiveRecord::Migration[8.1]
  def change
    create_table :screenshots do |t|
      t.references :project, null: false, foreign_key: true
      t.string :title, null: false
      t.integer :width
      t.integer :height
      t.integer :status, default: 0, null: false

      t.timestamps
    end
  end
end
