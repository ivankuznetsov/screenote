# frozen_string_literal: true

class FixDoorkeeperForeignKeysAndIndexes < ActiveRecord::Migration[8.1]
  def change
    # Fix FK cascade strategies (restrict -> cascade/nullify)
    remove_foreign_key :oauth_access_grants, :oauth_applications, column: :application_id
    remove_foreign_key :oauth_access_grants, :projects, column: :project_id
    remove_foreign_key :oauth_access_grants, :users, column: :resource_owner_id
    remove_foreign_key :oauth_access_tokens, :oauth_applications, column: :application_id
    remove_foreign_key :oauth_access_tokens, :projects, column: :project_id
    remove_foreign_key :oauth_access_tokens, :users, column: :resource_owner_id

    add_foreign_key :oauth_access_grants, :oauth_applications, column: :application_id, on_delete: :cascade
    add_foreign_key :oauth_access_grants, :projects, column: :project_id, on_delete: :nullify
    add_foreign_key :oauth_access_grants, :users, column: :resource_owner_id, on_delete: :cascade
    add_foreign_key :oauth_access_tokens, :oauth_applications, column: :application_id, on_delete: :cascade
    add_foreign_key :oauth_access_tokens, :projects, column: :project_id, on_delete: :nullify
    add_foreign_key :oauth_access_tokens, :users, column: :resource_owner_id, on_delete: :cascade

    # Add missing indexes on project_id
    add_index :oauth_access_grants, :project_id
    add_index :oauth_access_tokens, :project_id
  end
end
