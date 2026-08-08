# frozen_string_literal: true

require "digest"

class AdmissionLock
  class OutsideTransaction < StandardError; end
  STRIPES = 256

  class Record < ApplicationRecord
    self.table_name = "admission_locks"
  end

  class << self
    def email!(email)
      unless Record.connection.transaction_open?
        raise OutsideTransaction, "admission locks require an open outer transaction"
      end

      normalized_email = normalize(email)
      materialize_lock!(normalized_email)
      normalized_email
    end

    def normalize(email)
      email.to_s.strip.downcase.tap do |normalized_email|
        raise ArgumentError, "email must be present" if normalized_email.empty?
      end
    end

    private

    # A bounded, deterministic stripe serializes matching addresses before user
    # rows are inspected, including the case where no user exists yet. The row
    # contains no submitted address or reversible address digest.
    def materialize_lock!(normalized_email)
      slot = Digest::SHA256.digest(normalized_email).unpack1("n") % STRIPES
      return if update_lock!(slot)

      Record.create_or_find_by!(slot: slot)
      raise ActiveRecord::RecordNotFound unless update_lock!(slot)
    end

    def update_lock!(slot)
      Record.where(slot:).update_all(updated_at: Arel.sql("updated_at")) == 1
    end
  end
end
