# frozen_string_literal: true

class AllowTokenlessInstallationBootstrap < ActiveRecord::Migration[8.1]
  LEGACY_STATE_CONSTRAINT = <<~SQL.squish
    (deployment_mode = 'saas' AND state = 'saas' AND administrator_id IS NULL AND bootstrap_token_digest IS NULL AND claimed_at IS NULL) OR
    (deployment_mode = 'self_hosted' AND state = 'unclaimed' AND administrator_id IS NULL AND bootstrap_token_digest IS NOT NULL AND claimed_at IS NULL) OR
    (deployment_mode = 'self_hosted' AND state = 'claimed' AND administrator_id IS NOT NULL AND bootstrap_token_digest IS NULL AND claimed_at IS NOT NULL)
  SQL

  TOKENLESS_STATE_CONSTRAINT = <<~SQL.squish
    (deployment_mode = 'saas' AND state = 'saas' AND administrator_id IS NULL AND bootstrap_token_digest IS NULL AND claimed_at IS NULL) OR
    (deployment_mode = 'self_hosted' AND state = 'unclaimed' AND administrator_id IS NULL AND claimed_at IS NULL) OR
    (deployment_mode = 'self_hosted' AND state = 'claimed' AND administrator_id IS NOT NULL AND bootstrap_token_digest IS NULL AND claimed_at IS NOT NULL)
  SQL

  def up
    replace_state_constraint(TOKENLESS_STATE_CONSTRAINT)
  end

  def down
    tokenless_installations = select_value(<<~SQL.squish).to_i
      SELECT COUNT(*)
      FROM installations
      WHERE deployment_mode = 'self_hosted'
        AND state = 'unclaimed'
        AND bootstrap_token_digest IS NULL
    SQL
    if tokenless_installations.positive?
      raise ActiveRecord::IrreversibleMigration,
        "tokenless unclaimed installations cannot boot on the predecessor release"
    end

    replace_state_constraint(LEGACY_STATE_CONSTRAINT)
  end

  private

  def replace_state_constraint(expression)
    remove_check_constraint :installations, name: "installations_valid_state"
    add_check_constraint :installations, expression, name: "installations_valid_state"
  end
end
