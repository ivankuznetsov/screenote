# frozen_string_literal: true

class AddViewportToAnnotations < ActiveRecord::Migration[8.1]
  # Adds the viewport column for per-viewport annotation scoping (multi-viewport
  # capture feature, see plans/multi-viewport-screenshots.md).
  #
  # default: 0 backfills every existing annotation to :desktop in one pass, since
  # all existing annotations were created against the single desktop-assumed
  # image. A later migration (PR-5) will drop the default once application code
  # always writes the column explicitly.
  def change
    add_column :annotations, :viewport, :integer, null: false, default: 0
    add_index :annotations, [ :screenshot_id, :viewport ]
  end
end
