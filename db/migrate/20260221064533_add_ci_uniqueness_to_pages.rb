# frozen_string_literal: true

class AddCiUniquenessToPages < ActiveRecord::Migration[8.1]
  def up
    remove_index :pages, [:project_id, :name]
    add_index :pages, "project_id, LOWER(name)", unique: true, name: "index_pages_on_project_id_and_lower_name"
  end

  def down
    remove_index :pages, name: "index_pages_on_project_id_and_lower_name"
    add_index :pages, [:project_id, :name], unique: true
  end
end
