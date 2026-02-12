# frozen_string_literal: true

class CreateApiKeys < ActiveRecord::Migration[8.1]
  def change
    create_table :api_keys do |t|
      t.string :token, null: false
      t.string :name, null: false
      t.references :project, null: false, foreign_key: true
      t.datetime :last_used_at
      t.datetime :revoked_at

      t.timestamps
    end

    add_index :api_keys, :token, unique: true
  end
end
