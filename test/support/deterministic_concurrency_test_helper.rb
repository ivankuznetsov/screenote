# frozen_string_literal: true

require "timeout"

module DeterministicConcurrencyTestHelper
  BLOCKED_OPERATION_TIMEOUT = 0.2
  THREAD_TIMEOUT = 10

  private

  def with_one_shot_instance_method_barrier(model, method_name, predicate:)
    original = model.instance_method(method_name)
    own_method = model.instance_method(method_name) if model.instance_methods(false).include?(method_name)
    visibility = method_visibility(model, method_name)
    mutex = Mutex.new
    armed = true
    entered = Queue.new
    release = Queue.new

    model.define_method(method_name) do |*args, **kwargs, &block|
      matching_call = predicate.call(self, *args, **kwargs)
      should_block = matching_call && mutex.synchronize do
        next false unless armed

        armed = false
        true
      end

      if should_block
        entered << true
        release.pop
      end

      original.bind_call(self, *args, **kwargs, &block)
    end
    model.send(visibility, method_name)

    yield entered, release
  ensure
    release << true if release
    if own_method
      model.define_method(method_name, own_method)
      model.send(visibility, method_name)
    elsif original
      model.remove_method(method_name)
    end
  end

  def run_blocked_race(entered:, release:, first:, second:)
    first_result = Queue.new
    second_result = Queue.new
    first_connection = Queue.new
    second_connection = Queue.new
    second_started = Queue.new

    first_thread = concurrency_thread(first_result, first_connection, first)
    pop_with_timeout(entered)

    second_thread = concurrency_thread(second_result, second_connection, lambda do
      second_started << true
      second.call
    end)
    pop_with_timeout(second_started)

    first_connection_id = pop_with_timeout(first_connection)
    second_connection_id = pop_with_timeout(second_connection)
    assert_not_equal first_connection_id, second_connection_id
    assert_raises(Timeout::Error) do
      Timeout.timeout(BLOCKED_OPERATION_TIMEOUT) { second_result.pop }
    end

    release << true
    join_with_timeout(first_thread)
    join_with_timeout(second_thread)

    [ pop_with_timeout(first_result), pop_with_timeout(second_result) ]
  ensure
    release << true if release
    [ first_thread, second_thread ].compact.each do |thread|
      thread.kill if thread.alive?
    end
  end

  def concurrency_thread(result_queue, connection_queue, operation)
    Thread.new do
      ApplicationRecord.connection_pool.with_connection do |connection|
        connection_queue << connection.raw_connection.object_id
        result_queue << operation.call
      rescue StandardError => error
        result_queue << error
      end
    end
  end

  def assert_no_concurrency_exceptions(outcomes)
    exceptions = outcomes.grep(Exception)
    assert_empty exceptions, -> { exceptions.map(&:full_message).join("\n") }
  end

  def pop_with_timeout(queue)
    Timeout.timeout(THREAD_TIMEOUT) { queue.pop }
  end

  def join_with_timeout(thread)
    Timeout.timeout(THREAD_TIMEOUT) { thread.join }
  end

  def method_visibility(model, method_name)
    return :private if model.private_method_defined?(method_name)
    return :protected if model.protected_method_defined?(method_name)

    :public
  end
end
