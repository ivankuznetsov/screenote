# frozen_string_literal: true

class AddSnapshotIdToScreenshots < ActiveRecord::Migration[8.1]
  def change
    add_reference :screenshots, :snapshot, null: true, foreign_key: { on_delete: :nullify }
  end
end
