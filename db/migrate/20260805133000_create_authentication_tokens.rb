# frozen_string_literal: true

class CreateAuthenticationTokens < ActiveRecord::Migration[8.1]
  HEX_CHARACTERS = "0123456789abcdef"
  BASE64URL_CHARACTERS = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_-"
  PURPOSE_SUBJECT_CHECK = <<~SQL.squish.freeze
    (purpose = 0 AND project_invitation_id IS NOT NULL AND user_id IS NULL) OR
    (purpose IN (1, 2, 3, 4) AND user_id IS NOT NULL AND project_invitation_id IS NULL)
  SQL
  STATE_CHECK = <<~SQL.squish.freeze
    (state = 0 AND terminal_at IS NULL) OR
    (state IN (1, 2, 3) AND terminal_at IS NOT NULL AND terminal_at >= created_at)
  SQL

  def change
    create_table :authentication_tokens do |table|
      table.integer :purpose, null: false
      table.references :user, foreign_key: true
      table.references :project_invitation, foreign_key: true
      table.bigint :generation, null: false
      table.string :derivation_id, limit: 64, null: false
      table.string :derivation_key_id, limit: 46, null: false
      table.string :token_digest, limit: 64, null: false
      table.datetime :expires_at, null: false
      table.integer :state, null: false, default: 0
      table.datetime :terminal_at

      table.timestamps
    end

    add_index :authentication_tokens, :derivation_id, unique: true
    add_index :authentication_tokens, :token_digest, unique: true
    add_index :authentication_tokens,
      %i[purpose user_id generation],
      unique: true,
      where: "user_id IS NOT NULL",
      name: "index_auth_tokens_on_user_generation"
    add_index :authentication_tokens,
      %i[purpose project_invitation_id generation],
      unique: true,
      where: "project_invitation_id IS NOT NULL",
      name: "index_auth_tokens_on_invitation_generation"
    add_index :authentication_tokens, %i[purpose user_id],
      unique: true,
      where: "state = 0 AND user_id IS NOT NULL",
      name: "index_auth_tokens_on_outstanding_user"
    add_index :authentication_tokens, %i[purpose project_invitation_id],
      unique: true,
      where: "state = 0 AND project_invitation_id IS NOT NULL",
      name: "index_auth_tokens_on_outstanding_invitation"
    add_index :authentication_tokens, %i[state expires_at]
    add_index :authentication_tokens, %i[state derivation_key_id]

    add_check_constraint :authentication_tokens, "purpose IN (0, 1, 2, 3, 4)",
      name: "authentication_tokens_valid_purpose"
    add_check_constraint :authentication_tokens, PURPOSE_SUBJECT_CHECK,
      name: "authentication_tokens_exact_subject"
    add_check_constraint :authentication_tokens, "generation > 0",
      name: "authentication_tokens_positive_generation"
    add_check_constraint :authentication_tokens, hex_check(:derivation_id),
      name: "authentication_tokens_derivation_id_length"
    add_check_constraint :authentication_tokens, key_id_check,
      name: "authentication_tokens_key_id_format"
    add_check_constraint :authentication_tokens, hex_check(:token_digest),
      name: "authentication_tokens_digest_length"
    add_check_constraint :authentication_tokens, "expires_at > created_at",
      name: "authentication_tokens_future_expiry"
    add_check_constraint :authentication_tokens, "state IN (0, 1, 2, 3)",
      name: "authentication_tokens_valid_state"
    add_check_constraint :authentication_tokens, STATE_CHECK,
      name: "authentication_tokens_terminal_state"
  end

  private

  def hex_check(column)
    quoted = connection.quote_column_name(column)
    "length(#{quoted}) = 64 AND #{strip_characters(quoted, HEX_CHARACTERS)} = ''"
  end

  def key_id_check
    quoted = connection.quote_column_name(:derivation_key_id)
    payload = "substr(#{quoted}, 4)"
    <<~SQL.squish
      length(#{quoted}) = 46 AND substr(#{quoted}, 1, 3) = 'v1.' AND
      #{strip_characters(payload, BASE64URL_CHARACTERS)} = ''
    SQL
  end

  # Active Record dumps check constraints from the adapter that generated
  # db/schema.rb. Keep the expression valid in both SQLite and PostgreSQL so a
  # schema dumped by the self-hosted matrix can bootstrap a fresh SaaS database.
  def strip_characters(expression, allowed_characters)
    allowed_characters.each_char.reduce(expression) do |remaining, character|
      "replace(#{remaining}, #{connection.quote(character)}, '')"
    end
  end
end
