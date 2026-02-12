# frozen_string_literal: true

class FixResolvedByForeignKeyCascade < ActiveRecord::Migration[8.1]
  def change
    remove_foreign_key :annotations, :api_keys, column: :resolved_by_api_key_id
    add_foreign_key :annotations, :api_keys, column: :resolved_by_api_key_id, on_delete: :nullify

    remove_foreign_key :annotations, :users, column: :resolved_by_user_id
    add_foreign_key :annotations, :users, column: :resolved_by_user_id, on_delete: :nullify
  end
end
