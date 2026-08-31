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

    # Checked-in YAML only records intent. If no supervisor booted, if the
    # scheduler rejected the entries, or if its heartbeat died, cleanup never
    # runs and drafts accumulate while health still reports green.
    # Live proof is only required once the process has had time to produce it:
    # a readiness probe that demanded it from the first second would stop the
    # deployment it gates from ever coming up.
    test "a booting process is registered before a supervisor could have appeared" do
      with_supervisor_tables do
        assert Screenote::RecurringTasks.registered?(environment: "production")
      end
    end

    test "a supervised environment with no live scheduler is not registered once booted" do
      after_startup_grace do
        with_supervisor_tables do
          register_required_tasks

          assert_not Screenote::RecurringTasks.registered?(environment: "production")
        end
      end
    end

    test "a supervised environment whose queue database cannot be read fails closed" do
      assert_not Screenote::RecurringTasks.supervising?

      after_startup_grace do
        assert_not Screenote::RecurringTasks.registered?(environment: "production")
      end
    end

    test "a live scheduler that never registered the tasks is not supervising" do
      with_live_scheduler do
        assert_not Screenote::RecurringTasks.supervising?
      end
    end

    test "a scheduler whose heartbeat has died is not supervising" do
      with_live_scheduler(heartbeat: 1.hour.ago) do
        register_required_tasks

        assert_not Screenote::RecurringTasks.supervising?
      end
    end

    test "a live scheduler running the required tasks is supervising" do
      after_startup_grace do
        with_live_scheduler do
          register_required_tasks

          assert Screenote::RecurringTasks.supervising?
          assert Screenote::RecurringTasks.registered?(environment: "production")
        end
      end
    end

    test "readiness fails closed when cleanup is unscheduled" do
      original = Screenote::RecurringTasks.method(:registered?)
      Screenote::RecurringTasks.define_singleton_method(:registered?) { |**| false }

      assert_not Screenote::Readiness.new(storage_root: Dir.tmpdir).ready?
    ensure
      Screenote::RecurringTasks.define_singleton_method(:registered?, original)
    end

    private

    def after_startup_grace
      original = Screenote::RecurringTasks.booted_at
      Screenote::RecurringTasks.booted_at =
        original - Screenote::RecurringTasks::STARTUP_GRACE - 60
      yield
    ensure
      Screenote::RecurringTasks.booted_at = original
    end

    # The test environment runs one database and never loads the queue schema,
    # so the two Solid Queue tables this check reads are created here. Creating
    # them is what lets the real queries run rather than a stub of them.
    def with_supervisor_tables
      connection = SolidQueue::Process.connection
      connection.create_table(:solid_queue_processes, if_not_exists: true) do |t|
        t.string :kind, null: false
        t.datetime :last_heartbeat_at, null: false
        t.bigint :supervisor_id
        t.integer :pid, null: false
        t.string :hostname
        t.text :metadata
        t.datetime :created_at, null: false
        t.string :name, null: false
      end
      connection.create_table(:solid_queue_recurring_tasks, if_not_exists: true) do |t|
        t.string :key, null: false
        t.string :schedule, null: false
        t.string :command, limit: 2048
        t.string :class_name
        t.text :arguments
        t.string :queue_name
        t.integer :priority, default: 0
        t.boolean :static, default: true, null: false
        t.text :description
        t.timestamps
      end
      yield
    ensure
      connection.drop_table(:solid_queue_processes, if_exists: true)
      connection.drop_table(:solid_queue_recurring_tasks, if_exists: true)
    end

    def with_live_scheduler(heartbeat: Time.current)
      with_supervisor_tables do
        SolidQueue::Process.create!(
          kind: "Scheduler", last_heartbeat_at: heartbeat, pid: Process.pid,
          name: "scheduler-test-#{SecureRandom.hex(4)}"
        )
        yield
      end
    end

    def register_required_tasks
      Screenote::RecurringTasks::REQUIRED_TASKS.each do |key|
        SolidQueue::RecurringTask.create!(
          key: key, schedule: "every hour", class_name: "ImageAttachmentDraftCleanupJob", static: true
        )
      end
    end
  end
end
