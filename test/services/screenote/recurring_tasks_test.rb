# frozen_string_literal: true

require "test_helper"

module Screenote
  class RecurringTasksTest < ActiveSupport::TestCase
    test "every environment that supervises jobs schedules bounded attachment cleanup" do
      Screenote::RecurringTasks::SUPERVISED_ENVIRONMENTS.each do |environment|
        assert_empty Screenote::RecurringTasks.missing(environment: environment),
          "#{environment} does not schedule required recurring tasks"
      end
    end

    test "a supervised environment missing the cleanup task is not registered" do
      assert_not Screenote::RecurringTasks.registered?(
        environment: "production", required: %w[definitely_not_scheduled]
      )
    end

    test "readiness fails closed when cleanup is unscheduled" do
      original = Screenote::RecurringTasks.method(:registered?)
      Screenote::RecurringTasks.define_singleton_method(:registered?) { |**| false }

      assert_not Screenote::Readiness.new(storage_root: Dir.tmpdir).ready?
    ensure
      Screenote::RecurringTasks.define_singleton_method(:registered?, original)
    end
  end
end
