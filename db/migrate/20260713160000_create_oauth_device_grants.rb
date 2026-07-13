# frozen_string_literal: true

class CreateOauthDeviceGrants < ActiveRecord::Migration[8.1]
  def change
    create_table :oauth_device_grants do |t|
      t.references :application, null: false, foreign_key: { to_table: :oauth_applications, on_delete: :cascade }
      t.references :resource_owner, null: true, foreign_key: { to_table: :users, on_delete: :cascade }
      t.string :device_code, null: false, limit: 64
      t.string :user_code, null: false, limit: 11
      t.string :scopes, null: false
      t.datetime :expires_at, null: false
      t.integer :polling_interval, null: false, default: 5
      t.datetime :last_polled_at
      t.datetime :approved_at
      t.datetime :denied_at

      t.timestamps
    end

    add_index :oauth_device_grants, :device_code, unique: true
    add_index :oauth_device_grants, :user_code, unique: true
    add_index :oauth_device_grants, :expires_at
  end
end
