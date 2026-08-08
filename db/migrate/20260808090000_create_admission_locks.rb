# frozen_string_literal: true

class CreateAdmissionLocks < ActiveRecord::Migration[8.1]
  def change
    create_table :admission_locks do |table|
      table.integer :slot, null: false

      table.timestamps
    end

    add_index :admission_locks, :slot, unique: true
    add_check_constraint :admission_locks, "slot >= 0 AND slot < 256",
      name: "admission_locks_valid_slot"
  end
end
