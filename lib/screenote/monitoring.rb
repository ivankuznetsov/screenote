# frozen_string_literal: true

module Screenote
  module Monitoring
    module_function

    def notify(error, context: nil, **options)
      deployment = Deployment.current
      return false unless deployment.monitoring?

      if deployment.self_hosted?
        klass = error_class(error)
        Honeybadger.notify(
          error_class: klass,
          error_message: klass,
          backtrace: [],
          cause: nil,
          context: opaque_context(context)
        )
      else
        Honeybadger.notify(error, context: context, **options)
      end
    end

    def sanitize_notice!(notice)
      return notice unless Deployment.current.self_hosted?

      notice.error_message = notice.error_class
      notice.backtrace = []
      notice.cause = nil if notice.respond_to?(:cause=)
      notice.fingerprint = notice.error_class if notice.respond_to?(:fingerprint=)
      notice.tags = [] if notice.respond_to?(:tags=)
      notice.context = opaque_context(notice.context)
      notice.params = {}
      notice.session = {}
      notice.cgi_data = {}
      notice.url = nil
      notice.component = nil if notice.respond_to?(:component=)
      notice.action = nil if notice.respond_to?(:action=)
      notice.request_id = nil if notice.respond_to?(:request_id=)
      notice.breadcrumbs = []
      notice.details = nil
      notice.local_variables = nil
      notice.instance_variable_set(:@parsed_backtrace, nil)
      install_self_hosted_payload!(notice) if notice.is_a?(Honeybadger::Notice)
      notice
    end

    def error_class(error)
      error.is_a?(Exception) ? error.class.name : "Screenote::OperationalError"
    end
    private_class_method :error_class

    def opaque_context(context)
      context.to_h.each_with_object({}) do |(key, value), result|
        next unless key.to_s.end_with?("_id")
        next unless value.is_a?(String) || value.is_a?(Integer)

        result[key] = value
      end
    end
    private_class_method :opaque_context

    def install_self_hosted_payload!(notice)
      payload = {
        api_key: notice.api_key,
        notifier: Honeybadger::NOTIFIER,
        breadcrumbs: [],
        error: {
          token: notice.id,
          class: notice.error_class,
          message: notice.error_class,
          backtrace: [],
          fingerprint: notice.error_class,
          tags: [],
          causes: []
        },
        details: {},
        request: { context: opaque_context(notice.context) },
        server: { environment_name: "self_hosted" },
        correlation_context: {}
      }

      notice.define_singleton_method(:as_json) { |*_args| payload }
    end
    private_class_method :install_self_hosted_payload!
  end
end
