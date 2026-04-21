class CreateScreenshotImages < ActiveRecord::Migration[8.1]
  def change
    create_table :screenshot_images do |t|
      t.references :screenshot, null: false, foreign_key: { on_delete: :cascade }
      t.integer :viewport, null: false
      t.integer :status, null: false, default: 0
      t.integer :width
      t.integer :height

      t.timestamps
    end

    add_index :screenshot_images, [ :screenshot_id, :viewport ], unique: true
  end
end
