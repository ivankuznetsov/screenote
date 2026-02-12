# frozen_string_literal: true

class AddTokenDigestToApiKeys < ActiveRecord::Migration[8.1]
  def up
    add_column :api_keys, :token_digest, :string
    add_column :api_keys, :token_prefix, :string

    # Backfill existing plaintext tokens
    ApiKey.reset_column_information
    ApiKey.find_each do |key|
      key.update_columns(
        token_digest: Digest::SHA256.hexdigest(key.token),
        token_prefix: key.token.first(12)
      )
    end

    change_column_null :api_keys, :token_digest, false
    remove_index :api_keys, :token, unique: true
    remove_column :api_keys, :token
    add_index :api_keys, :token_digest, unique: true
  end

  def down
    remove_index :api_keys, :token_digest
    add_column :api_keys, :token, :string
    add_index :api_keys, :token, unique: true
    remove_column :api_keys, :token_digest
    remove_column :api_keys, :token_prefix
  end
end
