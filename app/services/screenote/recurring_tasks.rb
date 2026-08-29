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

    class << self
      def registered?(environment: Rails.env, required: REQUIRED_TASKS)
        return true unless supervised?(environment)

        missing(environment: environment, required: required).empty?
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
  end
end
