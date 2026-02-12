# frozen_string_literal: true

class AddForeignKeyToAnnotationsResolvedByApiKey < ActiveRecord::Migration[8.1]
  def change
    add_foreign_key :annotations, :api_keys, column: :resolved_by_api_key_id
  end
end
