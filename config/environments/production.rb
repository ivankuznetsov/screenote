# frozen_string_literal: true

require "active_support/core_ext/integer/time"

Rails.application.configure do
  deployment = Screenote::Deployment.current
  healthcheck_paths = %w[/up /ready].freeze

  # Settings specified here will take precedence over those in config/application.rb.

  # Code is not reloaded between requests.
  config.enable_reloading = false

  # Eager load code on boot for better performance and memory savings (ignored by Rake tasks).
  config.eager_load = true

  # Full error reports are disabled.
  config.consider_all_requests_local = false

  # Turn on fragment caching in view templates.
  config.action_controller.perform_caching = true

  # Cache assets for far-future expiry since they are all digest stamped.
  config.public_file_server.headers = { "cache-control" => "public, max-age=#{1.year.to_i}" }

  # Storage is selected by the validated deployment boundary.
  config.active_storage.service = deployment.active_storage_service

  # Transport security comes from the canonical public origin. Forwarded
  # headers affect request identity only when the peer is explicitly trusted.
  config.assume_ssl = false
  config.force_ssl = deployment.force_ssl?
  config.action_dispatch.trusted_proxies = deployment.trusted_proxies

  # DNS rebinding protection
  config.hosts = [ deployment.host ]
  config.host_authorization = { exclude: ->(request) { healthcheck_paths.include?(request.path) } }

  # Skip http-to-https redirects for local liveness and readiness probes.
  config.ssl_options = { redirect: { exclude: ->(request) { healthcheck_paths.include?(request.path) } } }

  # Log to STDOUT with the current request id as a default log tag.
  config.log_tags = [ :request_id ]
  config.logger   = ActiveSupport::TaggedLogging.logger($stdout)

  # Change to "debug" to log everything (including potentially personally-identifiable information!).
  config.log_level = ENV.fetch("RAILS_LOG_LEVEL", "info")

  # Prevent health checks from clogging up the logs.
  config.silence_healthcheck_path = /\A\/(?:up|ready)\z/

  # Don't log any deprecations.
  config.active_support.report_deprecations = false

  # Replace the default in-process memory cache store with a durable alternative.
  config.cache_store = :solid_cache_store
  config.action_controller.cache_store = Screenote::RateLimitStore.new

  # Replace the default in-process and non-durable queuing backend for Active Job.
  config.active_job.queue_adapter = :solid_queue
  config.solid_queue.connects_to = { database: { writing: :queue } }

  if deployment.mail_configuration.fetch(:provider) == :resend
    config.action_mailer.delivery_method = :resend
    config.action_mailer.perform_deliveries = true
    config.action_mailer.raise_delivery_errors = true
  elsif deployment.mail_configuration.fetch(:provider) == :smtp
    smtp = deployment.mail_configuration
    config.action_mailer.delivery_method = :smtp
    config.action_mailer.perform_deliveries = true
    config.action_mailer.smtp_settings = {
      address: smtp.fetch(:address),
      port: smtp.fetch(:port),
      user_name: smtp.fetch(:user_name),
      password: smtp.fetch(:password),
      domain: smtp.fetch(:domain),
      authentication: smtp.fetch(:authentication),
      enable_starttls_auto: smtp.fetch(:enable_starttls_auto)
    }
    config.action_mailer.raise_delivery_errors = true
  else
    config.action_mailer.perform_deliveries = false
    config.action_mailer.raise_delivery_errors = false
  end

  # Set host to be used by links generated in mailer templates.
  config.action_mailer.default_url_options = deployment.url_options

  # Set default URL options for routes (needed for background jobs/MCP tools)
  Rails.application.routes.default_url_options = deployment.url_options

  # Enable locale fallbacks for I18n (makes lookups for any locale fall back to
  # the I18n.default_locale when a translation cannot be found).
  config.i18n.fallbacks = true

  # Do not dump schema after migrations.
  config.active_record.dump_schema_after_migration = false

  # Only use :id for inspections in production.
  config.active_record.attributes_for_inspect = [ :id ]
end
