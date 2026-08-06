# frozen_string_literal: true

# screenote-edition: self_hosted

require "test_helper"
require "open3"

class ProductionBootTest < ActiveSupport::TestCase
  RUNTIME_KEYS = %w[
    SCREENOTE_EDITION SCREENOTE_BASE_URL SCREENOTE_BOOTSTRAP_TOKEN SCREENOTE_TRUSTED_PROXIES
    SCREENOTE_STORAGE SCREENOTE_SMTP_ENABLED SCREENOTE_GOOGLE_OAUTH_ENABLED
    SCREENOTE_GITHUB_OAUTH_ENABLED SCREENOTE_HONEYBADGER_ENABLED
    SCREENOTE_S3_ENDPOINT SCREENOTE_S3_REGION SCREENOTE_S3_BUCKET SCREENOTE_S3_PREFIX
    SCREENOTE_S3_ACCESS_KEY_ID SCREENOTE_S3_SECRET_ACCESS_KEY SCREENOTE_S3_PATH_STYLE
    SCREENOTE_S3_REQUEST_TIMEOUT SCREENOTE_S3_RETRY_LIMIT
    DATABASE_URL CACHE_DATABASE_URL QUEUE_DATABASE_URL CABLE_DATABASE_URL
    STRIPE_SECRET_KEY STRIPE_WEBHOOK_SECRET STRIPE_PRO_PRICE_ID RESEND_API_KEY MAILER_FROM
    GOOGLE_CLIENT_ID GOOGLE_CLIENT_SECRET GITHUB_CLIENT_ID GITHUB_CLIENT_SECRET
    HONEYBADGER_API_KEY HONEYBADGER_JS_API_KEY RABATA_ENDPOINT RABATA_REGION RABATA_BUCKET
    RABATA_ACCESS_KEY_ID RABATA_SECRET_ACCESS_KEY SCREENOTE_SAAS_OPERATOR_EMAIL
    SECRET_KEY_BASE SECRET_KEY_BASE_DUMMY
  ].freeze

  PROBE = <<~'RUBY'.squish.freeze
    puts({
      edition: Screenote::Deployment.current.edition,
      base_url: Screenote::Deployment.current.base_url,
      storage: Rails.application.config.active_storage.service,
      storage_class: ActiveStorage::Blob.service.class.name,
      rate_limit_store: ActionController::Base.cache_store.class.name,
      force_ssl: Rails.application.config.force_ssl,
      deliveries: Rails.application.config.action_mailer.perform_deliveries,
      oauth_providers: Screenote::Deployment.current.social_oauth_providers,
      oauth_request_validation:
        OmniAuth.config.request_validation_phase.is_a?(OmniAuth::AuthenticityTokenProtection) &&
          OmniAuth.config.request_validation_phase.options[:key] == :_csrf_token,
      omniauth_full_host: OmniAuth.config.full_host,
      dimension_job_after_commit: ScreenshotDimensionJob.enqueue_after_transaction_commit,
      password_reset_route: Rails.application.routes.named_routes.key?(:new_password),
      route_url_options: Rails.application.routes.default_url_options
    }.to_json)
  RUBY

  PROXY_PROBE = <<~'RUBY'.freeze
    app = Rails.application
    direct = Rack::MockRequest.env_for(
      "http://notes.example.test/help",
      "REMOTE_ADDR" => "203.0.113.10",
      "HTTP_HOST" => "notes.example.test",
      "HTTP_X_FORWARDED_FOR" => "198.51.100.77",
      "HTTP_X_FORWARDED_PROTO" => "https",
      "HTTP_X_FORWARDED_HOST" => "notes.example.test"
    )
    proxied = Rack::MockRequest.env_for(
      "http://notes.example.test/help",
      "REMOTE_ADDR" => "10.2.3.4",
      "HTTP_HOST" => "notes.example.test",
      "HTTP_X_FORWARDED_FOR" => "198.51.100.77",
      "HTTP_X_FORWARDED_PROTO" => "https",
      "HTTP_X_FORWARDED_HOST" => "notes.example.test"
    )
    direct_response = app.call(direct)
    proxied_response = app.call(proxied)
    puts({
      direct_status: direct_response.first,
      direct_location: direct_response.second["location"],
      proxied_status: proxied_response.first
    }.to_json)
  RUBY

  test "provider-free self hosted production boot uses HTTP canonical configuration" do
    stdout, stderr, status = boot(self_hosted_environment)

    assert status.success?, stderr
    payload = JSON.parse(stdout.lines.last)
    assert_equal "self_hosted", payload.fetch("edition")
    assert_equal "http://screenote.internal:3000", payload.fetch("base_url")
    assert_equal "self_hosted_local", payload.fetch("storage")
    assert_equal "ActiveStorage::Service::DiskService", payload.fetch("storage_class")
    assert_equal "Screenote::RateLimitStore", payload.fetch("rate_limit_store")
    assert_equal false, payload.fetch("force_ssl")
    assert_equal false, payload.fetch("deliveries")
    assert_empty payload.fetch("oauth_providers")
    assert_equal true, payload.fetch("oauth_request_validation")
    assert_equal "http://screenote.internal:3000", payload.fetch("omniauth_full_host")
    assert_equal true, payload.fetch("dimension_job_after_commit")
    assert_equal false, payload.fetch("password_reset_route")
    assert_equal "screenote.internal", payload.dig("route_url_options", "host")
    assert_equal 3000, payload.dig("route_url_options", "port")
    assert_equal "http", payload.dig("route_url_options", "protocol")
  end

  test "HTTPS self hosted production boot enables transport security" do
    stdout, stderr, status = boot(
      self_hosted_environment.merge("SCREENOTE_BASE_URL" => "https://notes.example.test")
    )

    assert status.success?, stderr
    payload = JSON.parse(stdout.lines.last)
    assert_equal true, payload.fetch("force_ssl")
    assert_equal "https", payload.dig("route_url_options", "protocol")
  end

  test "SaaS production boot retains all hosted capabilities" do
    stdout, stderr, status = boot(saas_environment)

    assert status.success?, stderr
    payload = JSON.parse(stdout.lines.last)
    assert_equal "saas", payload.fetch("edition")
    assert_equal "rabata", payload.fetch("storage")
    assert_equal "ActiveStorage::Service::S3Service", payload.fetch("storage_class")
    assert_equal %w[google_oauth2 github], payload.fetch("oauth_providers")
    assert_equal true, payload.fetch("deliveries")
    assert_equal true, payload.fetch("force_ssl")
    assert_equal true, payload.fetch("oauth_request_validation")
    assert_equal "https://screenote.ai", payload.fetch("omniauth_full_host")
    assert_equal true, payload.fetch("dimension_job_after_commit")
    assert_equal true, payload.fetch("password_reset_route")
  end

  test "production boot rejects missing edition and partial providers" do
    _stdout, stderr, status = boot("SCREENOTE_BASE_URL" => "https://notes.example.test")
    assert_not status.success?
    assert_includes stderr, "SCREENOTE_EDITION"

    _stdout, stderr, status = boot(
      self_hosted_environment.merge("SCREENOTE_GOOGLE_OAUTH_ENABLED" => "1")
    )
    assert_not status.success?
    assert_includes stderr, "GOOGLE_CLIENT_ID"
  end

  test "production boot rejects missing origin and weak application secret" do
    _stdout, stderr, status = boot(
      "SCREENOTE_EDITION" => "self_hosted",
      "SCREENOTE_BOOTSTRAP_TOKEN" => "b" * 43
    )
    assert_not status.success?
    assert_includes stderr, "SCREENOTE_BASE_URL"

    _stdout, stderr, status = boot(
      self_hosted_environment.merge("SECRET_KEY_BASE" => "short")
    )
    assert_not status.success?
    assert_includes stderr, "SECRET_KEY_BASE"
  end

  test "HTTPS production redirects direct spoofed forwarding but accepts an explicit proxy" do
    stdout, stderr, status = boot(
      self_hosted_environment.merge(
        "SCREENOTE_BASE_URL" => "https://notes.example.test",
        "SCREENOTE_TRUSTED_PROXIES" => "10.0.0.0/8"
      ),
      probe: PROXY_PROBE
    )

    assert status.success?, stderr
    payload = JSON.parse(stdout.lines.last)
    assert_equal 301, payload.fetch("direct_status"), payload.inspect
    assert_equal "https://notes.example.test/help", payload.fetch("direct_location")
    assert_equal 200, payload.fetch("proxied_status"), payload.inspect
  end

  test "self hosted S3 production boot loads the prefixed storage service" do
    stdout, stderr, status = boot(
      self_hosted_environment.merge(
        "SCREENOTE_STORAGE" => "s3",
        "SCREENOTE_S3_ENDPOINT" => "https://objects.example.test",
        "SCREENOTE_S3_REGION" => "local",
        "SCREENOTE_S3_BUCKET" => "screenote-private",
        "SCREENOTE_S3_PREFIX" => "team-one/screenshots",
        "SCREENOTE_S3_ACCESS_KEY_ID" => "test-access",
        "SCREENOTE_S3_SECRET_ACCESS_KEY" => "test-secret"
      )
    )

    assert status.success?, stderr
    payload = JSON.parse(stdout.lines.last)
    assert_equal "self_hosted_s3", payload.fetch("storage")
    assert_equal "ActiveStorage::Service::PrefixedS3Service", payload.fetch("storage_class")
  end

  test "dummy asset build boots without runtime configuration" do
    stdout, stderr, status = boot("SECRET_KEY_BASE_DUMMY" => "1")

    assert status.success?, stderr
    payload = JSON.parse(stdout.lines.last)
    assert_equal "saas", payload.fetch("edition")
    assert_equal "https://screenote.ai", payload.fetch("base_url")
  end

  private

  def boot(environment = nil, probe: PROBE, **keyword_environment)
    environment ||= keyword_environment
    clean_environment = RUNTIME_KEYS.to_h { |key| [ key, nil ] }
    clean_environment.merge!(
      "RAILS_ENV" => "production",
      "SECRET_KEY_BASE" => "a" * 64,
      "RAILS_LOG_TO_STDOUT" => nil
    )
    clean_environment.merge!(environment)

    Open3.capture3(clean_environment, "bin/rails", "runner", probe, chdir: Rails.root.to_s)
  end

  def self_hosted_environment
    {
      "SCREENOTE_EDITION" => "self_hosted",
      "SCREENOTE_BASE_URL" => "http://screenote.internal:3000",
      "SCREENOTE_BOOTSTRAP_TOKEN" => "b" * 43
    }
  end

  def saas_environment
    {
      "SCREENOTE_EDITION" => "saas",
      "SCREENOTE_BASE_URL" => "https://screenote.ai",
      "DATABASE_URL" => "postgres://screenote:secret@127.0.0.1/screenote",
      "CACHE_DATABASE_URL" => "postgres://screenote:secret@127.0.0.1/cache",
      "QUEUE_DATABASE_URL" => "postgres://screenote:secret@127.0.0.1/queue",
      "CABLE_DATABASE_URL" => "postgres://screenote:secret@127.0.0.1/cable",
      "STRIPE_SECRET_KEY" => "stripe-secret",
      "STRIPE_WEBHOOK_SECRET" => "stripe-webhook-secret",
      "STRIPE_PRO_PRICE_ID" => "price-pro",
      "RESEND_API_KEY" => "resend-secret",
      "MAILER_FROM" => "noreply@screenote.ai",
      "GOOGLE_CLIENT_ID" => "google-client",
      "GOOGLE_CLIENT_SECRET" => "google-secret",
      "GITHUB_CLIENT_ID" => "github-client",
      "GITHUB_CLIENT_SECRET" => "github-secret",
      "HONEYBADGER_API_KEY" => "honeybadger-server-secret",
      "HONEYBADGER_JS_API_KEY" => "honeybadger-browser-secret",
      "SCREENOTE_SAAS_OPERATOR_EMAIL" => "operator@screenote.ai",
      "RABATA_ENDPOINT" => "https://s3.us-east-1.rabata.io",
      "RABATA_REGION" => "us-east-1",
      "RABATA_BUCKET" => "screenote",
      "RABATA_ACCESS_KEY_ID" => "rabata-access",
      "RABATA_SECRET_ACCESS_KEY" => "rabata-secret"
    }
  end
end
