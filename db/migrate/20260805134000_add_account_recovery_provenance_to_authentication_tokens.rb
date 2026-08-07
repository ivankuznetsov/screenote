# frozen_string_literal: true

class AddAccountRecoveryProvenanceToAuthenticationTokens < ActiveRecord::Migration[8.1]
  RECOVERY_PURPOSE = 4
  ISSUER_CHECK = <<~SQL.squish.freeze
    (purpose = #{RECOVERY_PURPOSE} AND issued_by_user_id IS NOT NULL) OR
    (purpose <> #{RECOVERY_PURPOSE} AND issued_by_user_id IS NULL)
  SQL

  def up
    existing_ids = select_values(<<~SQL.squish).map(&:to_i)
      SELECT id
      FROM authentication_tokens
      WHERE purpose = #{RECOVERY_PURPOSE}
      ORDER BY id
    SQL
    if existing_ids.any?
      raise ActiveRecord::MigrationError,
        "Account-recovery provenance preflight failed before mutation (authentication token IDs): #{existing_ids.join(', ')}"
    end

    add_reference :authentication_tokens,
      :issued_by_user,
      foreign_key: { to_table: :users },
      index: false
    add_index :authentication_tokens,
      %i[issued_by_user_id state],
      where: "purpose = #{RECOVERY_PURPOSE}",
      name: "index_auth_tokens_on_recovery_issuer_state"
    add_check_constraint :authentication_tokens,
      ISSUER_CHECK,
      name: "authentication_tokens_recovery_issuer"
  end

  def down
    raise ActiveRecord::IrreversibleMigration,
      "Immutable account-recovery issuer provenance cannot be safely discarded"
  end
end
