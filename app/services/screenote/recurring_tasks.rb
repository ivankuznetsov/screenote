# frozen_string_literal: true

module Screenote
  # Reads the Solid Queue recurring schedule that a deployment will actually
  # supervise. Deployment health depends on it: bounded cleanup that is never
  # scheduled leaks draft bytes silently, so a missing task must fail visibly
  # rather than degrade quietly.
  class RecurringTasks
    CONFIGURATION_PATH = "config/recurring.yml"
    REQUIRED_TASKS = %w[
      clear_expired_image_attachment_drafts
      reconcile_image_attachments
    ].freeze
    # Environments that boot a Solid Queue supervisor. Development and test run
    # jobs inline or on demand, so there is no schedule for them to be missing
    # from.
    SUPERVISED_ENVIRONMENTS = %w[production].freeze
    # Solid Queue supervisors heartbeat once a minute by default. Three missed
    # beats is a stopped supervisor, not a slow one.
    HEARTBEAT_GRACE = 5.minutes
    # A scheduler cannot have registered its tasks or written a heartbeat before
    # the process that supervises it has finished booting. Readiness gates the
    # deployment, so demanding live proof from the first second would stop the
    # deployment from ever coming up. After this window the proof is required.
    STARTUP_GRACE = 5.minutes

    class << self
      # Assigned once when the class loads, which under eager loading is process
      # boot. Tests move it to exercise the post-boot requirement.
      attr_accessor :booted_at

      # The schedule file only records what a deployment intends to run.
      # Readiness has to answer whether it is actually running: a supervisor
      # that never booted, a scheduler that rejected the recurring entries, or
      # one whose heartbeat has died all leave bounded cleanup unexecuted while
      # the checked-in YAML still parses. Both halves are therefore required,
      # and anything that cannot be established reports unhealthy.
      def registered?(environment: Rails.env, required: REQUIRED_TASKS, now: Time.current)
        return true unless supervised?(environment)
        return false unless missing(environment: environment, required: required).empty?
        return true if supervising?(required: required, now: now)

        booting?
      end

      def booting?
        Process.clock_gettime(Process::CLOCK_MONOTONIC) - booted_at < STARTUP_GRACE
      end

      # Reads the live supervisor state Solid Queue keeps in the queue database:
      # each booted scheduler registers its static recurring entries and every
      # running process heartbeats.
      def supervising?(required: REQUIRED_TASKS, now: Time.current)
        return false unless defined?(SolidQueue::Process) && defined?(SolidQueue::RecurringTask)

        scheduler_alive?(now: now) && (required - registered_task_keys).empty?
      rescue StandardError => error
        Screenote::Monitoring.notify(error, context: { check: "recurring_task_supervisor" })
        false
      end

      def scheduler_alive?(now: Time.current)
        SolidQueue::Process
          .where(kind: "Scheduler")
          .where(last_heartbeat_at: (now - HEARTBEAT_GRACE)..)
          .exists?
      end

      def registered_task_keys
        SolidQueue::RecurringTask.where(static: true).pluck(:key).map(&:to_s)
      end

      def supervised?(environment)
        SUPERVISED_ENVIRONMENTS.include?(environment.to_s)
      end

      def missing(environment: Rails.env, required: REQUIRED_TASKS)
        configured = task_names(environment: environment)
        required - configured
      end

      def task_names(environment: Rails.env)
        schedule(environment: environment).keys.map(&:to_s)
      end

      # The schedule ships with the image and cannot change without a redeploy,
      # so it is read once per environment rather than on every health probe.
      def schedule(environment: Rails.env)
        key = environment.to_s
        cache = (@schedules ||= {})
        cache.fetch(key) { cache[key] = load_schedule(key) }
      end

      def reset_schedule_cache!
        @schedules = {}
      end

      private

      def load_schedule(environment)
        path = Rails.root.join(CONFIGURATION_PATH)
        return {} unless path.exist?

        loaded = YAML.safe_load(ERB.new(path.read).result, aliases: true) || {}
        loaded.fetch(environment, nil) || {}
      end
    end

    self.booted_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)
  end
end
