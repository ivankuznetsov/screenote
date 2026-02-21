class CreatePages < ActiveRecord::Migration[8.1]
  def change
    create_table :pages do |t|
      t.references :project, null: false, foreign_key: true
      t.string :name, null: false

      t.timestamps
    end

    add_index :pages, [ :project_id, :name ], unique: true
  end
end
