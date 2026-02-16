# frozen_string_literal: true

class CreateDoorkeeperTables < ActiveRecord::Migration[8.1]
  def change
    create_table :oauth_applications do |t|
      t.string  :name,    null: false
      t.string  :uid,     null: false
      t.string  :secret
      t.text    :redirect_uri, null: false
      t.string  :scopes,       null: false, default: ""
      t.boolean :confidential, null: false, default: false
      t.boolean :dynamic,      null: false, default: false
      t.timestamps             null: false
    end

    add_index :oauth_applications, :uid, unique: true

    create_table :oauth_access_grants do |t|
      t.references :resource_owner,  null: false
      t.references :application,     null: false
      t.string   :token,             null: false
      t.integer  :expires_in,        null: false
      t.text     :redirect_uri,      null: false
      t.string   :scopes,            null: false, default: ""
      t.string   :code_challenge
      t.string   :code_challenge_method
      t.integer  :project_id
      t.datetime :created_at,        null: false
      t.datetime :revoked_at
    end

    add_index :oauth_access_grants, :token, unique: true
    add_foreign_key :oauth_access_grants, :oauth_applications, column: :application_id
    add_foreign_key :oauth_access_grants, :projects, column: :project_id
    add_foreign_key :oauth_access_grants, :users, column: :resource_owner_id

    create_table :oauth_access_tokens do |t|
      t.references :resource_owner, index: true
      t.references :application, null: false
      t.string  :token, null: false
      t.string  :refresh_token
      t.integer :expires_in
      t.string  :scopes
      t.integer :project_id
      t.datetime :created_at, null: false
      t.datetime :revoked_at
      t.string :previous_refresh_token, null: false, default: ""
    end

    add_index :oauth_access_tokens, :token, unique: true
    add_index :oauth_access_tokens, :refresh_token, unique: true
    add_foreign_key :oauth_access_tokens, :oauth_applications, column: :application_id
    add_foreign_key :oauth_access_tokens, :projects, column: :project_id
    add_foreign_key :oauth_access_tokens, :users, column: :resource_owner_id
  end
end
