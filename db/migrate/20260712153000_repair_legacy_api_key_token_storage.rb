# frozen_string_literal: true

require "digest"

class RepairLegacyApiKeyTokenStorage < ActiveRecord::Migration[8.1]
  def up
    if column_exists?(:api_keys, :token)
      convert_legacy_tokens
    elsif secure_schema?
      say "api_keys already uses digested token storage"
    else
      raise ActiveRecord::MigrationError, "Unsupported api_keys schema; refusing a partial token-storage migration"
    end
  end

  def down
    raise ActiveRecord::IrreversibleMigration, "API key plaintext tokens cannot be reconstructed from SHA-256 digests"
  end

  private

  def convert_legacy_tokens
    add_column :api_keys, :token_digest, :string unless column_exists?(:api_keys, :token_digest)
    add_column :api_keys, :token_prefix, :string unless column_exists?(:api_keys, :token_prefix)

    say_with_time "Digesting legacy API key tokens" do
      connection.select_rows("SELECT id, token FROM #{connection.quote_table_name(:api_keys)}").each do |id, token|
        if token.nil? || token.empty?
          raise ActiveRecord::MigrationError, "Cannot migrate an API key with a blank token"
        end

        connection.update(<<~SQL.squish)
          UPDATE #{connection.quote_table_name(:api_keys)}
          SET token_digest = #{connection.quote(Digest::SHA256.hexdigest(token))},
              token_prefix = #{connection.quote(token.first(12))}
          WHERE id = #{connection.quote(id)}
        SQL
      end
    end

    ensure_unique_digests!
    change_column_null :api_keys, :token_digest, false
    remove_index :api_keys, :token if index_exists?(:api_keys, :token)
    remove_column :api_keys, :token
    replace_digest_index_with_unique_index
  end

  def ensure_unique_digests!
    duplicate_groups = connection.select_value(<<~SQL.squish).to_i
      SELECT COUNT(*)
      FROM (
        SELECT token_digest
        FROM #{connection.quote_table_name(:api_keys)}
        GROUP BY token_digest
        HAVING COUNT(*) > 1
      ) duplicate_digests
    SQL
    return if duplicate_groups.zero?

    raise ActiveRecord::MigrationError, "Cannot migrate duplicate API key tokens"
  end

  def replace_digest_index_with_unique_index
    return if index_exists?(:api_keys, :token_digest, unique: true)

    remove_index :api_keys, :token_digest if index_exists?(:api_keys, :token_digest)
    add_index :api_keys, :token_digest, unique: true
  end

  def secure_schema?
    columns = connection.columns(:api_keys).index_by(&:name)
    digest = columns["token_digest"]

    digest.present? && !digest.null &&
      columns.key?("token_prefix") &&
      index_exists?(:api_keys, :token_digest, unique: true)
  end
end
