class AddCompositeIndexToScreenshots < ActiveRecord::Migration[8.1]
  def change
    add_index :screenshots, %i[project_id created_at]
  end
end
