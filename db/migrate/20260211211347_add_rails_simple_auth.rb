# frozen_string_literal: true

class AddRailsSimpleAuth < ActiveRecord::Migration[8.1]
  def change
    create_table :users do |t|
      t.string :email, null: false
      t.string :password_digest, null: false
      t.datetime :confirmed_at
      t.string :oauth_provider
      t.string :oauth_uid

      t.timestamps
    end

    add_index :users, :email, unique: true
    add_index :users, :confirmed_at

    create_table :sessions do |t|
      t.references :user, null: false, foreign_key: true
      t.string :ip_address
      t.string :user_agent

      t.timestamps
    end

    add_index :sessions, :created_at
  end
end
