# frozen_string_literal: true

class DatabaseRetry
  class NestedInvocation < StandardError; end
  class OpenTransaction < StandardError; end

  class Exhausted < StandardError
    attr_reader :attempts, :original_error

    def initialize(original_error, attempts:)
      @original_error = original_error
      @attempts = attempts
      super("database operation remained busy after #{attempts} attempts")
    end
  end

  MAX_ATTEMPTS = 3
  EXECUTION_STATE_KEY = :screenote_database_retry_active
  DEFAULT_BACKOFF = ->(attempt) { 0.01 * (2**(attempt - 1)) }
  DEFAULT_SLEEPER = ->(delay) { Kernel.sleep(delay) }
  POSTGRESQL_RETRYABLE_ERRORS = [
    ActiveRecord::Deadlocked,
    ActiveRecord::SerializationFailure,
    ActiveRecord::LockWaitTimeout
  ].freeze

  class << self
    def call(
      connection: ApplicationRecord.connection,
      backoff: DEFAULT_BACKOFF,
      sleeper: DEFAULT_SLEEPER
    )
      raise OpenTransaction, "database retries must wrap the outermost transaction" if connection.transaction_open?
      raise NestedInvocation, "database retry wrappers cannot be nested" if retry_active?

      with_retry_state do
        attempts = 0

        begin
          attempts += 1
          yield attempts
        rescue StandardError => error
          raise unless retryable?(error, connection: connection)
          raise Exhausted.new(error, attempts: attempts) if attempts >= MAX_ATTEMPTS

          sleeper.call(backoff.call(attempts))
          retry
        end
      end
    end

    private

    def retryable?(error, connection:)
      case connection.adapter_name
      when /PostgreSQL/i
        POSTGRESQL_RETRYABLE_ERRORS.any? { |error_class| error.is_a?(error_class) }
      when /SQLite/i
        sqlite_retryable?(error)
      else
        false
      end
    end

    def sqlite_retryable?(error)
      sqlite_retryable_errors = []
      sqlite_retryable_errors << SQLite3::BusyException if defined?(SQLite3::BusyException)
      sqlite_retryable_errors << SQLite3::LockedException if defined?(SQLite3::LockedException)

      exception_chain(error).any? do |exception|
        sqlite_retryable_errors.any? { |error_class| exception.is_a?(error_class) }
      end
    end

    def exception_chain(error)
      Enumerator.produce(error, &:cause).take_while(&:itself)
    end

    def retry_active?
      ActiveSupport::IsolatedExecutionState[EXECUTION_STATE_KEY]
    end

    def with_retry_state
      previous = ActiveSupport::IsolatedExecutionState[EXECUTION_STATE_KEY]
      ActiveSupport::IsolatedExecutionState[EXECUTION_STATE_KEY] = true
      yield
    ensure
      if previous.nil?
        ActiveSupport::IsolatedExecutionState.delete(EXECUTION_STATE_KEY)
      else
        ActiveSupport::IsolatedExecutionState[EXECUTION_STATE_KEY] = previous
      end
    end
  end
end
