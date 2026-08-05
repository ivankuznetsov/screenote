# frozen_string_literal: true

class CreateInstallations < ActiveRecord::Migration[8.1]
  def change
    create_table :installations do |t|
      t.string :singleton_key, null: false, default: "screenote"
      t.string :deployment_mode, null: false
      t.string :state, null: false
      t.string :storage_service, null: false
      t.string :storage_namespace_fingerprint, limit: 64, null: false
      t.string :bootstrap_token_digest, limit: 64
      t.references :administrator, foreign_key: { to_table: :users }, index: { unique: true }
      t.datetime :claimed_at

      t.timestamps
    end

    add_index :installations, :singleton_key, unique: true
    add_check_constraint :installations,
      "singleton_key = 'screenote'",
      name: "installations_singleton_key"
    add_check_constraint :installations,
      "deployment_mode IN ('saas', 'self_hosted')",
      name: "installations_deployment_mode"
    add_check_constraint :installations,
      "length(storage_namespace_fingerprint) = 64",
      name: "installations_storage_fingerprint"
    add_check_constraint :installations,
      <<~SQL.squish,
        (deployment_mode = 'saas' AND storage_service = 'rabata') OR
        (deployment_mode = 'self_hosted' AND storage_service IN ('self_hosted_local', 'self_hosted_s3'))
      SQL
      name: "installations_storage_service"
    add_check_constraint :installations,
      <<~SQL.squish,
        (deployment_mode = 'saas' AND state = 'saas' AND administrator_id IS NULL AND bootstrap_token_digest IS NULL AND claimed_at IS NULL) OR
        (deployment_mode = 'self_hosted' AND state = 'unclaimed' AND administrator_id IS NULL AND bootstrap_token_digest IS NOT NULL AND claimed_at IS NULL) OR
        (deployment_mode = 'self_hosted' AND state = 'claimed' AND administrator_id IS NOT NULL AND bootstrap_token_digest IS NULL AND claimed_at IS NOT NULL)
      SQL
      name: "installations_valid_state"
  end
end
