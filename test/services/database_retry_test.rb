# frozen_string_literal: true

require "test_helper"

class DatabaseRetryTest < ActiveSupport::TestCase
  Connection = Data.define(:adapter_name, :transaction_open?)

  test "retries PostgreSQL concurrency failures at most three times with injected backoff" do
    connection = Connection.new(adapter_name: "PostgreSQL", transaction_open?: false)
    attempts = []
    delays = []

    result = DatabaseRetry.call(
      connection: connection,
      backoff: ->(attempt) { attempt.fdiv(100) },
      sleeper: ->(delay) { delays << delay }
    ) do |attempt|
      attempts << attempt
      raise ActiveRecord::Deadlocked, "deadlock" if attempt < 3

      :completed
    end

    assert_equal :completed, result
    assert_equal [ 1, 2, 3 ], attempts
    assert_equal [ 0.01, 0.02 ], delays
  end

  test "retries each supported PostgreSQL failure class" do
    connection = Connection.new(adapter_name: "PostgreSQL", transaction_open?: false)

    [ ActiveRecord::SerializationFailure, ActiveRecord::LockWaitTimeout ].each do |error_class|
      attempts = 0
      result = DatabaseRetry.call(connection: connection, sleeper: ->(_delay) { }) do
        attempts += 1
        raise error_class, "retryable" if attempts == 1

        :completed
      end

      assert_equal :completed, result
      assert_equal 2, attempts
    end
  end

  test "retries only busy and locked SQLite failures from the exception cause chain" do
    connection = Connection.new(adapter_name: "SQLite", transaction_open?: false)

    [ SQLite3::BusyException, SQLite3::LockedException ].each do |error_class|
      attempts = 0
      result = DatabaseRetry.call(connection: connection, sleeper: ->(_delay) { }) do
        attempts += 1
        raise sqlite_wrapper(error_class.new("retryable")) if attempts == 1

        :completed
      end

      assert_equal :completed, result
      assert_equal 2, attempts
    end
  end

  test "raises a stable exhausted error with the final failure and cause after three attempts" do
    connection = Connection.new(adapter_name: "PostgreSQL", transaction_open?: false)
    failures = 3.times.map { |index| ActiveRecord::Deadlocked.new("deadlock #{index + 1}") }
    attempts = 0

    error = assert_raises(DatabaseRetry::Exhausted) do
      DatabaseRetry.call(connection: connection, sleeper: ->(_delay) { }) do
        attempts += 1
        raise failures.fetch(attempts - 1)
      end
    end

    assert_equal 3, attempts
    assert_equal 3, error.attempts
    assert_same failures.last, error.original_error
    assert_same failures.last, error.cause
  end

  test "does not retry integrity, generic statement, or programming errors" do
    connection = Connection.new(adapter_name: "PostgreSQL", transaction_open?: false)
    errors = [
      ActiveRecord::RecordNotUnique.new("duplicate"),
      ActiveRecord::StatementInvalid.new("invalid SQL"),
      NoMethodError.new("programming error")
    ]

    errors.each do |expected|
      attempts = 0
      actual = assert_raises(expected.class) do
        DatabaseRetry.call(connection: connection, sleeper: ->(_delay) { }) do
          attempts += 1
          raise expected
        end
      end

      assert_same expected, actual
      assert_equal 1, attempts
    end
  end

  test "unsupported adapters never classify failures as retryable" do
    connection = Connection.new(adapter_name: "Mysql2", transaction_open?: false)
    expected = ActiveRecord::Deadlocked.new("not supported")
    attempts = 0

    actual = assert_raises(ActiveRecord::Deadlocked) do
      DatabaseRetry.call(connection: connection, sleeper: ->(_delay) { }) do
        attempts += 1
        raise expected
      end
    end

    assert_same expected, actual
    assert_equal 1, attempts
  end

  test "SQLite failure classification remains fail closed when optional exception constants are absent" do
    connection = Connection.new(adapter_name: "SQLite", transaction_open?: false)
    busy_exception = SQLite3.send(:remove_const, :BusyException)
    locked_exception = SQLite3.send(:remove_const, :LockedException)
    expected = ActiveRecord::StatementInvalid.new("SQLite write failed")
    attempts = 0

    actual = assert_raises(ActiveRecord::StatementInvalid) do
      DatabaseRetry.call(connection: connection, sleeper: ->(_delay) { }) do
        attempts += 1
        raise expected
      end
    end

    assert_same expected, actual
    assert_equal 1, attempts
  ensure
    SQLite3.const_set(:BusyException, busy_exception) if busy_exception
    SQLite3.const_set(:LockedException, locked_exception) if locked_exception
  end

  test "rejects calls inside an open transaction" do
    connection = Connection.new(adapter_name: "SQLite", transaction_open?: true)

    assert_raises(DatabaseRetry::OpenTransaction) do
      DatabaseRetry.call(connection: connection, sleeper: ->(_delay) { }) { :completed }
    end
  end

  test "rejects nested retry wrappers and clears its execution state" do
    connection = Connection.new(adapter_name: "SQLite", transaction_open?: false)

    assert_raises(DatabaseRetry::NestedInvocation) do
      DatabaseRetry.call(connection: connection, sleeper: ->(_delay) { }) do
        DatabaseRetry.call(connection: connection, sleeper: ->(_delay) { }) { :completed }
      end
    end

    assert_equal :completed,
      DatabaseRetry.call(connection: connection, sleeper: ->(_delay) { }) { :completed }
  end

  test "restores a pre-existing false execution-state marker" do
    connection = Connection.new(adapter_name: "SQLite", transaction_open?: false)
    state = ActiveSupport::IsolatedExecutionState
    state[DatabaseRetry::EXECUTION_STATE_KEY] = false

    assert_equal :completed,
      DatabaseRetry.call(connection: connection, sleeper: ->(_delay) { }) { :completed }
    assert_equal false, state[DatabaseRetry::EXECUTION_STATE_KEY]
  ensure
    state&.delete(DatabaseRetry::EXECUTION_STATE_KEY)
  end

  private

  def sqlite_wrapper(cause)
    raise ActiveRecord::StatementInvalid.new("SQLite write failed"), cause: cause
  rescue ActiveRecord::StatementInvalid => error
    error
  end
end
