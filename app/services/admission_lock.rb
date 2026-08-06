# frozen_string_literal: true

require "digest"

class AdmissionLock
  class OutsideTransaction < StandardError; end
  class UnsupportedAdapter < StandardError; end

  DOMAIN_SEPARATOR = "screenote:admission-email:v1\0"
  SQLITE_WRITER_LOCK_SQL =
    "UPDATE users SET updated_at = updated_at WHERE id = (SELECT MIN(id) FROM users)"

  class << self
    def email!(email, connection: ApplicationRecord.connection)
      raise OutsideTransaction, "admission locks require an open outer transaction" unless connection.transaction_open?

      normalized_email = normalize(email)

      case connection.adapter_name
      when /PostgreSQL/i
        connection.select_value("SELECT pg_advisory_xact_lock(#{advisory_key(normalized_email)})")
      when /SQLite/i
        # Rails 8.1 opens the outer SQLite transaction in IMMEDIATE mode. This
        # write materializes a lazy transaction and never attempts to replace
        # an existing outer transaction with a nested savepoint.
        connection.execute(SQLITE_WRITER_LOCK_SQL)
      else
        raise UnsupportedAdapter, "admission locks do not support #{connection.adapter_name}"
      end

      normalized_email
    end

    def normalize(email)
      email.to_s.strip.downcase.tap do |normalized_email|
        raise ArgumentError, "email must be present" if normalized_email.empty?
      end
    end

    private

    def advisory_key(normalized_email)
      Digest::SHA256.digest("#{DOMAIN_SEPARATOR}#{normalized_email}").unpack1("q>")
    end
  end
end
