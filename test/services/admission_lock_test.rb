# frozen_string_literal: true

require "test_helper"

class AdmissionLockTest < ActiveSupport::TestCase
  Connection = Data.define(:transaction_open?)

  setup do
    AdmissionLock::Record.delete_all
  end

  test "normalizes email and materializes a bounded lock stripe" do
    normalized_email = AdmissionLock.email!(" Person@Example.COM\n")

    assert_equal "person@example.com", normalized_email
    assert_includes 0...AdmissionLock::STRIPES, AdmissionLock::Record.pick(:slot)
    assert_equal %w[created_at id slot updated_at], AdmissionLock::Record.column_names.sort
    assert AdmissionLock::Record.connection.check_constraints(:admission_locks)
      .any? { |constraint| constraint.name == "admission_locks_valid_slot" }
  end

  test "reuses the same lock key for the same normalized email" do
    AdmissionLock.email!("person@example.com")
    AdmissionLock.email!(" PERSON@example.com ")

    assert_equal 1, AdmissionLock::Record.count
  end

  test "fails closed when a new lock row still cannot be updated" do
    attempts = 0
    replacement = lambda do |*|
      attempts += 1
      false
    end

    with_lock_update(replacement) do
      assert_raises(ActiveRecord::RecordNotFound) do
        AdmissionLock.email!("person@example.com")
      end
    end

    assert_equal 2, attempts
    assert_equal 1, AdmissionLock::Record.count
  end

  test "fails before issuing SQL when no outer transaction is open" do
    connection = Connection.new(transaction_open?: false)

    with_record_connection(connection) do
      assert_raises(AdmissionLock::OutsideTransaction) do
        AdmissionLock.email!("person@example.com")
      end
    end
  end

  test "rejects blank email before materializing the lock" do
    assert_raises(ArgumentError) { AdmissionLock.email!(" \n") }
  end

  private

  def with_record_connection(connection)
    singleton = AdmissionLock::Record.singleton_class
    original = AdmissionLock::Record.method(:connection)
    singleton.define_method(:connection) { connection }
    yield
  ensure
    singleton&.define_method(:connection, original) if original
  end

  def with_lock_update(replacement)
    singleton = AdmissionLock.singleton_class
    original = AdmissionLock.method(:update_lock!)
    singleton.define_method(:update_lock!, replacement)
    singleton.send(:private, :update_lock!)
    yield
  ensure
    singleton&.define_method(:update_lock!, original) if original
    singleton&.send(:private, :update_lock!)
  end
end
