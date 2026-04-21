# frozen_string_literal: true

class CreateScreenshotImages < ActiveRecord::Migration[8.1]
  def change
    create_table :screenshot_images do |t|
      # FK uses default RESTRICT (not cascade) so parent destroys flow through
      # the `dependent: :destroy` on Screenshot#has_many :screenshot_images,
      # which triggers Active Storage blob purge callbacks. Cascade at the DB
      # level would bypass those callbacks and orphan S3 blobs.
      t.references :screenshot, null: false, foreign_key: true
      t.integer :viewport, null: false
      t.integer :status, null: false, default: 0
      t.integer :width
      t.integer :height

      t.timestamps
    end

    add_index :screenshot_images, [ :screenshot_id, :viewport ], unique: true
  end
end
