# frozen_string_literal: true

require "test_helper"

class AdmissionLockTest < ActiveSupport::TestCase
  class RecordingConnection
    attr_reader :adapter_name, :statements

    def initialize(adapter_name:, transaction_open:)
      @adapter_name = adapter_name
      @transaction_open = transaction_open
      @statements = []
    end

    def transaction_open?
      @transaction_open
    end

    def select_value(statement)
      statements << [ :select_value, statement ]
    end

    def execute(statement)
      statements << [ :execute, statement ]
    end
  end

  test "normalizes email and takes a stable PostgreSQL transaction advisory lock" do
    connection = RecordingConnection.new(adapter_name: "PostgreSQL", transaction_open: true)

    normalized_email = AdmissionLock.email!(" Person@Example.COM\n", connection: connection)

    assert_equal "person@example.com", normalized_email
    assert_equal [
      [ :select_value, "SELECT pg_advisory_xact_lock(-4008866821215467476)" ]
    ], connection.statements
  end

  test "uses an already-open SQLite transaction and forces its writer lock" do
    connection = RecordingConnection.new(adapter_name: "SQLite", transaction_open: true)

    normalized_email = AdmissionLock.email!(" ALICE@example.com ", connection: connection)

    assert_equal "alice@example.com", normalized_email
    assert_equal [
      [ :execute, "UPDATE users SET updated_at = updated_at WHERE id = (SELECT MIN(id) FROM users)" ]
    ], connection.statements
  end

  test "fails before issuing SQL when no outer transaction is open" do
    connection = RecordingConnection.new(adapter_name: "PostgreSQL", transaction_open: false)

    assert_raises(AdmissionLock::OutsideTransaction) do
      AdmissionLock.email!("person@example.com", connection: connection)
    end
    assert_empty connection.statements
  end

  test "rejects blank email and unsupported adapters" do
    postgres = RecordingConnection.new(adapter_name: "PostgreSQL", transaction_open: true)
    mysql = RecordingConnection.new(adapter_name: "Mysql2", transaction_open: true)

    assert_raises(ArgumentError) { AdmissionLock.email!(" \n", connection: postgres) }
    assert_raises(AdmissionLock::UnsupportedAdapter) do
      AdmissionLock.email!("person@example.com", connection: mysql)
    end
    assert_empty postgres.statements
    assert_empty mysql.statements
  end
end
