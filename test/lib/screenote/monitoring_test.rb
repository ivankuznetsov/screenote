# frozen_string_literal: true

require "test_helper"
require "socket"

class Screenote::MonitoringTest < ActiveSupport::TestCase
  test "disabled monitoring does not call Honeybadger" do
    deployment = self_hosted_deployment
    calls = with_deployment(deployment) do
      capture_honeybadger_calls do
        Screenote::Monitoring.notify(
          RuntimeError.new("comment sentinel"),
          context: { email: "person@example.test", project_id: 123 }
        )
      end
    end

    assert_empty calls
  end

  test "self hosted monitoring exports only exception class and opaque ids" do
    deployment = self_hosted_deployment(
      "SCREENOTE_HONEYBADGER_ENABLED" => "1",
      "HONEYBADGER_API_KEY" => "monitoring-key"
    )

    calls = with_deployment(deployment) do
      capture_honeybadger_calls do
        Screenote::Monitoring.notify(
          RuntimeError.new("comment sentinel"),
          context: {
            user_id: 42,
            email: "person@example.test",
            project_name: "private project",
            request_url: "http://private.example.test/path"
          }
        )
      end
    end

    assert_equal 1, calls.length
    assert_equal "RuntimeError", calls.first.first.fetch(:error_class)
    assert_equal "RuntimeError", calls.first.first.fetch(:error_message)
    assert_empty calls.first.first.fetch(:backtrace)
    assert_nil calls.first.first.fetch(:cause)
    assert_equal({ user_id: 42 }, calls.first.first.fetch(:context))
    assert_not_includes calls.inspect, "comment sentinel"
    assert_not_includes calls.inspect, "person@example.test"
    assert_not_includes calls.inspect, "private project"
  end

  test "self hosted automatic notices discard request and user data" do
    notice = Struct.new(
      :error_message,
      :error_class,
      :context,
      :params,
      :session,
      :cgi_data,
      :url,
      :breadcrumbs,
      :details,
      :local_variables,
      :backtrace,
      :cause,
      :fingerprint,
      :tags,
      :component,
      :action,
      :request_id,
      keyword_init: true
    ).new(
      error_message: "comment sentinel",
      error_class: "RuntimeError",
      context: { project_id: 7, email: "person@example.test", page_name: "private" },
      params: { token: "secret" },
      session: { user_email: "person@example.test" },
      cgi_data: { "HTTP_AUTHORIZATION" => "Bearer secret" },
      url: "http://private.example.test/project",
      breadcrumbs: [ "private action" ],
      details: { screenshot: "metadata" },
      local_variables: { comment: "sentinel" },
      backtrace: [ "/private/project/comment.rb:1" ],
      cause: RuntimeError.new("smtp password=private"),
      tags: [ "private-project" ],
      component: "SecretController",
      action: "private_action",
      request_id: "private-request"
    )

    sanitized = with_deployment(
      self_hosted_deployment(
        "SCREENOTE_HONEYBADGER_ENABLED" => "1",
        "HONEYBADGER_API_KEY" => "monitoring-key"
      )
    ) { Screenote::Monitoring.sanitize_notice!(notice) }

    assert_equal "RuntimeError", sanitized.error_message
    assert_equal({ project_id: 7 }, sanitized.context)
    assert_empty sanitized.params
    assert_empty sanitized.session
    assert_empty sanitized.cgi_data
    assert_nil sanitized.url
    assert_empty sanitized.breadcrumbs
    assert_nil sanitized.details
    assert_nil sanitized.local_variables
    assert_empty sanitized.backtrace
    assert_nil sanitized.cause
    assert_empty sanitized.tags
    assert_nil sanitized.component
    assert_nil sanitized.action
    assert_nil sanitized.request_id
  end

  test "serialized Honeybadger notice contains no nested exception sentinel" do
    inner = RuntimeError.new("smtp password=private")
    inner.set_backtrace([ "/private/smtp-password.rb:1" ])
    outer = RuntimeError.new("comment and email person@example.test")
    outer.set_backtrace([ "/private/comment.rb:2" ])
    outer.define_singleton_method(:cause) { inner }
    notice = Honeybadger::Notice.new(
      Honeybadger.config,
      exception: outer,
      context: { project_id: 7, email: "person@example.test" },
      component: "PrivateController",
      action: "secret",
      tags: "private"
    )

    sanitized = with_deployment(
      self_hosted_deployment(
        "SCREENOTE_HONEYBADGER_ENABLED" => "1",
        "HONEYBADGER_API_KEY" => "monitoring-key"
      )
    ) { Screenote::Monitoring.sanitize_notice!(notice) }

    serialized = sanitized.to_json
    payload = JSON.parse(serialized, symbolize_names: true)

    assert_not_includes serialized, "smtp password"
    assert_not_includes serialized, "person@example.test"
    assert_not_includes serialized, "/private/"
    assert_not_includes serialized, "PrivateController"
    assert_not_includes serialized, "comment and email"
    assert_equal({ environment_name: "self_hosted" }, payload.fetch(:server))
    assert_equal({ project_id: 7 }, payload.dig(:request, :context))
    assert_empty payload.fetch(:breadcrumbs)
    assert_empty payload.fetch(:details)
    assert_empty payload.fetch(:correlation_context)
    assert_not_includes serialized, Rails.root.to_s
    assert_not_includes serialized, Socket.gethostname
    assert_not_includes payload.fetch(:server).keys, :stats
    assert_not_includes payload.fetch(:server).keys, :pid
  end

  private

  def capture_honeybadger_calls
    calls = []
    original = Honeybadger.method(:notify)
    Honeybadger.define_singleton_method(:notify) do |*args, **options|
      calls << [ args.first || options, args.first ? options : {} ]
    end
    yield
    calls
  ensure
    Honeybadger.define_singleton_method(:notify, original)
  end

  def with_deployment(deployment)
    previous = Screenote::Deployment.current
    Screenote::Deployment.instance_variable_set(:@current, deployment)
    yield
  ensure
    Screenote::Deployment.instance_variable_set(:@current, previous)
  end

  def self_hosted_deployment(overrides = {})
    Screenote::Deployment.new(
      {
        "SCREENOTE_EDITION" => "self_hosted",
        "SCREENOTE_BASE_URL" => "http://screenote.internal",
        "SECRET_KEY_BASE" => "a" * 64
      }.merge(overrides),
      production: true
    )
  end
end
