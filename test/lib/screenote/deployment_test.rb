# frozen_string_literal: true

require "test_helper"

class Screenote::DeploymentTest < ActiveSupport::TestCase
  test "configured deployment can be reset without retaining stale state" do
    previous = Screenote::Deployment.current
    configured = Screenote::Deployment.configure!(self_hosted_environment, production: true)

    assert_same configured, Screenote::Deployment.current
    Screenote::Deployment.reset!
    assert_raises(Screenote::Deployment::ConfigurationError) { Screenote::Deployment.current }
  ensure
    Screenote::Deployment.instance_variable_set(:@current, previous)
  end

  test "development defaults to SaaS and parses an IPv6 origin" do
    default = deployment({}, production: false)
    ipv6 = deployment({ "SCREENOTE_BASE_URL" => "http://[2001:db8::1]:3000" }, production: false)

    assert default.saas?
    assert_equal "http://localhost:3000", default.base_url
    assert_equal "http://[2001:db8::1]:3000", ipv6.base_url
    assert_equal "[2001:db8::1]", ipv6.host
    assert_equal "http", ipv6.protocol
    assert_equal 3000, ipv6.port
  end

  test "production requires an explicit supported edition" do
    error = assert_raises(Screenote::Deployment::ConfigurationError) do
      deployment({}, production: true)
    end

    assert_match "SCREENOTE_EDITION", error.message

    error = assert_raises(Screenote::Deployment::ConfigurationError) do
      deployment({ "SCREENOTE_EDITION" => "enterprise" }, production: true)
    end

    assert_match "saas or self_hosted", error.message
  end

  test "production requires a canonical origin source and strong application secret" do
    error = assert_raises(Screenote::Deployment::ConfigurationError) do
      deployment(
        {
          "SCREENOTE_EDITION" => "self_hosted",
          "SECRET_KEY_BASE" => "a" * 64
        },
        production: true
      )
    end
    assert_match "SCREENOTE_BASE_URL", error.message

    error = assert_raises(Screenote::Deployment::ConfigurationError) do
      deployment(
        {
          "SCREENOTE_EDITION" => "self_hosted",
          "SCREENOTE_BASE_URL" => "http://screenote.internal",
          "SECRET_KEY_BASE" => "too-short"
        },
        production: true
      )
    end
    assert_match "SECRET_KEY_BASE", error.message
  end

  test "native ONCE configuration derives the canonical origin from its hostname and TLS mode" do
    https = deployment(
      native_once_environment("ONCE_HOST" => "notes.example.test", "DISABLE_SSL" => "false"),
      production: true
    )
    http = deployment(
      native_once_environment("ONCE_HOST" => "screenote.internal", "DISABLE_SSL" => "true"),
      production: true
    )

    assert_equal "https://notes.example.test", https.base_url
    assert_equal({ host: "notes.example.test", protocol: "https" }, https.url_options)
    assert https.force_ssl?
    assert_equal "http://screenote.internal", http.base_url
    assert_not http.force_ssl?
  end

  test "native ONCE hostname must be one hostname and agree with an explicit override" do
    [ "https://notes.example.test", "notes.example.test/path", "bad host", "notes.example.test:443" ].each do |host|
      error = assert_raises(Screenote::Deployment::ConfigurationError) do
        deployment(native_once_environment("ONCE_HOST" => host), production: true)
      end
      assert_match "ONCE_HOST", error.message
    end

    error = assert_raises(Screenote::Deployment::ConfigurationError) do
      deployment(
        native_once_environment(
          "ONCE_HOST" => "notes.example.test",
          "SCREENOTE_BASE_URL" => "https://other.example.test"
        ),
        production: true
      )
    end
    assert_match "must match", error.message
  end

  test "asset compilation does not require runtime configuration" do
    config = deployment({ "SECRET_KEY_BASE_DUMMY" => "1" }, production: true)

    assert config.asset_build?
    assert config.saas?
    assert_equal "https://screenote.ai", config.base_url
  end

  test "minimal self hosted configuration has no optional providers" do
    config = deployment(self_hosted_environment, production: true)

    assert config.self_hosted?
    assert_equal "http://screenote.internal:3000", config.base_url
    assert_equal "screenote.internal", config.host
    assert_equal 3000, config.port
    assert_not config.secure_cookies?
    assert_not config.force_ssl?
    assert_not config.billing?
    assert_not config.mail?
    assert_not config.monitoring?
    assert_empty config.social_oauth_providers
    assert_equal :self_hosted_local, config.active_storage_service
    assert_equal 64, config.storage_namespace_fingerprint.length
    assert_equal 1, config.forwarded_client_hops
  end

  test "https origin drives secure transport and route defaults" do
    config = deployment(self_hosted_environment("SCREENOTE_BASE_URL" => "https://notes.example.test"), production: true)

    assert config.force_ssl?
    assert config.secure_cookies?
    assert_equal({ host: "notes.example.test", protocol: "https" }, config.url_options)
  end

  test "ONCE TLS mode must match the canonical origin" do
    mismatches = [
      {
        "SCREENOTE_BASE_URL" => "https://notes.example.test",
        "DISABLE_SSL" => "true"
      },
      { "DISABLE_SSL" => "false" }
    ]

    mismatches.each do |override|
      error = assert_raises(Screenote::Deployment::ConfigurationError) do
        deployment(self_hosted_environment(override), production: true)
      end

      assert_equal(
        "DISABLE_SSL must be true exactly when SCREENOTE_BASE_URL uses http",
        error.message
      )
    end

    once_https = deployment(
      self_hosted_environment(
        "SCREENOTE_BASE_URL" => "https://notes.example.test",
        "DISABLE_SSL" => "false"
      ),
      production: true
    )
    once_http = deployment(self_hosted_environment("DISABLE_SSL" => "true"), production: true)

    assert_equal "https", once_https.protocol
    assert_equal "http", once_http.protocol
  end

  test "malformed ONCE SSL settings fail closed" do
    error = assert_raises(Screenote::Deployment::ConfigurationError) do
      deployment(self_hosted_environment("DISABLE_SSL" => "sometimes"), production: true)
    end

    assert_equal "DISABLE_SSL must be true or false", error.message
  end

  test "canonical origin rejects credentials path query fragment and unsupported schemes" do
    invalid_origins = [
      "ftp://notes.example.test",
      "https://user:secret@notes.example.test",
      "https://notes.example.test/reviews",
      "https://notes.example.test?tenant=one",
      "https://notes.example.test#reviews",
      "https://notes.example.test/%2e%2e"
    ]

    invalid_origins.each do |origin|
      error = assert_raises(Screenote::Deployment::ConfigurationError) do
        deployment(self_hosted_environment("SCREENOTE_BASE_URL" => origin), production: true)
      end
      assert_match "SCREENOTE_BASE_URL", error.message
    end
  end

  test "malformed canonical origin is reported as configuration failure" do
    error = assert_raises(Screenote::Deployment::ConfigurationError) do
      deployment(self_hosted_environment("SCREENOTE_BASE_URL" => "https://["), production: true)
    end

    assert_equal "SCREENOTE_BASE_URL must be a valid HTTP(S) origin", error.message
  end

  test "trusted proxies must be explicit valid CIDRs" do
    config = deployment(
      self_hosted_environment("SCREENOTE_TRUSTED_PROXIES" => "10.0.0.0/8, 2001:db8::/32"),
      production: true
    )

    assert_equal 2, config.trusted_proxies.length
    assert config.trusted_proxies.first.include?("10.1.2.3")
    assert config.trusted_proxies.second.include?("2001:db8::1")

    error = assert_raises(Screenote::Deployment::ConfigurationError) do
      deployment(self_hosted_environment("SCREENOTE_TRUSTED_PROXIES" => "private-network"), production: true)
    end
    assert_match "SCREENOTE_TRUSTED_PROXIES", error.message

    error = assert_raises(Screenote::Deployment::ConfigurationError) do
      deployment(self_hosted_environment("SCREENOTE_TRUSTED_PROXIES" => "0.0.0.0/0"), production: true)
    end
    assert_match "entire internet", error.message
  end

  test "trusted proxy parsing ignores empty comma-separated entries" do
    config = deployment(
      self_hosted_environment("SCREENOTE_TRUSTED_PROXIES" => " , 10.0.0.0/8, "),
      production: true
    )

    assert_equal 1, config.trusted_proxies.length
    assert config.trusted_proxies.first.include?("10.1.2.3")
  end

  test "forwarded client hops bind the supported two-hop path to one proxy host" do
    assert_equal 1, deployment(self_hosted_environment, production: true).forwarded_client_hops
    assert_nil deployment(self_hosted_environment, production: true).forwarded_proxy_host
    assert_equal 2, deployment(
      self_hosted_environment(
        "SCREENOTE_FORWARDED_CLIENT_HOPS" => "2",
        "SCREENOTE_FORWARDED_PROXY_HOST" => "once-proxy"
      ),
      production: true
    ).forwarded_client_hops

    config = deployment(
      self_hosted_environment(
        "SCREENOTE_FORWARDED_CLIENT_HOPS" => "2",
        "SCREENOTE_FORWARDED_PROXY_HOST" => "once-proxy"
      ),
      production: true
    )
    assert_equal "once-proxy", config.forwarded_proxy_host

    [ "192.168.192.2", "2001:db8::2" ].each do |host|
      config = deployment(
        self_hosted_environment(
          "SCREENOTE_FORWARDED_CLIENT_HOPS" => "2",
          "SCREENOTE_FORWARDED_PROXY_HOST" => host
        ),
        production: true
      )
      assert_equal host, config.forwarded_proxy_host
    end

    [ "0", "-1", "3", "two" ].each do |value|
      error = assert_raises(Screenote::Deployment::ConfigurationError) do
        deployment(
          self_hosted_environment("SCREENOTE_FORWARDED_CLIENT_HOPS" => value),
          production: true
        )
      end

      assert_equal "SCREENOTE_FORWARDED_CLIENT_HOPS must be 1 or 2", error.message
    end

    error = assert_raises(Screenote::Deployment::ConfigurationError) do
      deployment(
        self_hosted_environment("SCREENOTE_FORWARDED_CLIENT_HOPS" => "2"),
        production: true
      )
    end
    assert_equal "SCREENOTE_FORWARDED_PROXY_HOST is required for a two-hop proxy chain", error.message

    invalid_hosts = [
      "bad host", ".proxy", "proxy.", "proxy..internal", "-proxy", "proxy-",
      "192.168.0.0/24", "192.168.192.2/32", "2001:db8::2/128", "x" * 254
    ]
    invalid_hosts.each do |host|
      error = assert_raises(Screenote::Deployment::ConfigurationError) do
        deployment(
          self_hosted_environment(
            "SCREENOTE_FORWARDED_CLIENT_HOPS" => "2",
            "SCREENOTE_FORWARDED_PROXY_HOST" => host
          ),
          production: true
        )
      end
      assert_equal "SCREENOTE_FORWARDED_PROXY_HOST must be a valid hostname or IP address", error.message
    end
  end

  test "self hosted storage profile fails closed" do
    error = assert_raises(Screenote::Deployment::ConfigurationError) do
      deployment(self_hosted_environment("SCREENOTE_STORAGE" => "shared"), production: true)
    end
    assert_equal "SCREENOTE_STORAGE must be local or s3", error.message
  end

  test "optional self hosted providers reject partial selection" do
    {
      "SCREENOTE_SMTP_ENABLED" => "1",
      "SCREENOTE_GOOGLE_OAUTH_ENABLED" => "1",
      "SCREENOTE_GITHUB_OAUTH_ENABLED" => "1",
      "SCREENOTE_HONEYBADGER_ENABLED" => "1",
      "SCREENOTE_STORAGE" => "s3"
    }.each do |key, value|
      error = assert_raises(Screenote::Deployment::ConfigurationError) do
        deployment(self_hosted_environment(key => value), production: true)
      end
      assert_match(/requires/, error.message, key)
    end
  end

  test "ONCE SMTP variables implicitly enable self hosted mail" do
    config = deployment(
      self_hosted_environment(
        "SMTP_ADDRESS" => "smtp.example.test",
        "SMTP_PORT" => "587",
        "SMTP_USERNAME" => "screenote",
        "SMTP_PASSWORD" => "smtp-secret",
        "MAILER_FROM_ADDRESS" => "screenote@example.test"
      ),
      production: true
    )

    assert config.mail?
    assert_equal :smtp, config.mail_configuration.fetch(:provider)
    assert_equal "screenote@example.test", config.mail_configuration.fetch(:from)
  end

  test "implicit SMTP selection fails closed when ONCE settings are incomplete" do
    error = assert_raises(Screenote::Deployment::ConfigurationError) do
      deployment(
        self_hosted_environment(
          "SMTP_ADDRESS" => "smtp.example.test",
          "MAILER_FROM_ADDRESS" => "screenote@example.test"
        ),
        production: true
      )
    end

    assert_match "Selected SMTP provider requires", error.message
    assert_includes error.message, "SMTP_PORT"
    assert_includes error.message, "SMTP_USERNAME"
    assert_includes error.message, "SMTP_PASSWORD"
  end

  test "explicit false keeps self hosted SMTP disabled when ONCE settings are present" do
    config = deployment(
      self_hosted_environment(
        "SCREENOTE_SMTP_ENABLED" => "false",
        "SMTP_ADDRESS" => "smtp.example.test",
        "SMTP_PORT" => "587",
        "SMTP_USERNAME" => "screenote",
        "SMTP_PASSWORD" => "smtp-secret",
        "MAILER_FROM_ADDRESS" => "screenote@example.test"
      ),
      production: true
    )

    assert_not config.mail?
  end

  test "MAILER_FROM takes precedence over its ONCE alias" do
    config = deployment(
      self_hosted_environment(
        "SMTP_ADDRESS" => "smtp.example.test",
        "SMTP_PORT" => "587",
        "SMTP_USERNAME" => "screenote",
        "SMTP_PASSWORD" => "smtp-secret",
        "MAILER_FROM" => "preferred@example.test",
        "MAILER_FROM_ADDRESS" => "once@example.test"
      ),
      production: true
    )

    assert_equal "preferred@example.test", config.mail_configuration.fetch(:from)
  end

  test "complete optional providers expose only their selected capabilities" do
    config = deployment(
      self_hosted_environment.merge(
        "SCREENOTE_STORAGE" => "s3",
        "SCREENOTE_S3_ENDPOINT" => "https://objects.example.test",
        "SCREENOTE_S3_REGION" => "local",
        "SCREENOTE_S3_BUCKET" => "screenote-private",
        "SCREENOTE_S3_PREFIX" => "team-one",
        "SCREENOTE_S3_ACCESS_KEY_ID" => "access-key",
        "SCREENOTE_S3_SECRET_ACCESS_KEY" => "secret-key",
        "SCREENOTE_SMTP_ENABLED" => "1",
        "SMTP_ADDRESS" => "smtp.example.test",
        "SMTP_PORT" => "587",
        "SMTP_USERNAME" => "screenote",
        "SMTP_PASSWORD" => "smtp-secret",
        "MAILER_FROM" => "screenote@example.test",
        "SCREENOTE_GOOGLE_OAUTH_ENABLED" => "1",
        "GOOGLE_CLIENT_ID" => "google-client",
        "GOOGLE_CLIENT_SECRET" => "google-secret",
        "SCREENOTE_HONEYBADGER_ENABLED" => "1",
        "HONEYBADGER_API_KEY" => "server-key"
      ),
      production: true
    )

    assert_equal :self_hosted_s3, config.active_storage_service
    assert config.mail?
    assert config.monitoring?
    assert_equal [ :google_oauth2 ], config.social_oauth_providers
    assert_not config.billing?
  end

  test "S3 endpoint rejects credentials path query and fragment" do
    invalid_endpoints = [
      "https://user:secret@objects.example.test",
      "https://objects.example.test/team-one",
      "https://objects.example.test?bucket=screenote",
      "https://objects.example.test#private"
    ]

    invalid_endpoints.each do |endpoint|
      error = assert_raises(Screenote::Deployment::ConfigurationError) do
        deployment(
          self_hosted_environment.merge(
            "SCREENOTE_STORAGE" => "s3",
            "SCREENOTE_S3_ENDPOINT" => endpoint,
            "SCREENOTE_S3_REGION" => "local",
            "SCREENOTE_S3_BUCKET" => "screenote-private",
            "SCREENOTE_S3_PREFIX" => "team-one",
            "SCREENOTE_S3_ACCESS_KEY_ID" => "access-key",
            "SCREENOTE_S3_SECRET_ACCESS_KEY" => "secret-key"
          ),
          production: true
        )
      end

      assert_match "SCREENOTE_S3_ENDPOINT", error.message
    end
  end

  test "S3 endpoint syntax and namespace components are validated" do
    error = assert_raises(Screenote::Deployment::ConfigurationError) do
      deployment(s3_environment("SCREENOTE_S3_ENDPOINT" => "https://["), production: true)
    end
    assert_equal "SCREENOTE_S3_ENDPOINT must be a valid HTTP(S) endpoint", error.message

    [ "team//one", "team/..", "a" * 64 ].each do |prefix|
      error = assert_raises(Screenote::Deployment::ConfigurationError) do
        deployment(s3_environment("SCREENOTE_S3_PREFIX" => prefix), production: true)
      end
      assert_match(/slash-separated object namespace/, error.message)
    end
  end

  test "boolean and numeric provider settings accept explicit false and reject malformed bounds" do
    disabled = deployment(self_hosted_environment("SCREENOTE_SMTP_ENABLED" => "false"), production: true)
    blank = deployment(self_hosted_environment("SCREENOTE_SMTP_ENABLED" => "   "), production: true)
    assert_not disabled.mail?
    assert_not blank.mail?

    error = assert_raises(Screenote::Deployment::ConfigurationError) do
      deployment(self_hosted_environment("SCREENOTE_SMTP_ENABLED" => "sometimes"), production: true)
    end
    assert_equal "SCREENOTE_SMTP_ENABLED must be true or false", error.message

    [
      [ "SCREENOTE_S3_REQUEST_TIMEOUT", "0", /positive integer/ ],
      [ "SCREENOTE_S3_REQUEST_TIMEOUT", "many", /positive integer/ ],
      [ "SCREENOTE_S3_RETRY_LIMIT", "-1", /non-negative integer/ ],
      [ "SCREENOTE_S3_RETRY_LIMIT", "many", /non-negative integer/ ]
    ].each do |key, value, message|
      error = assert_raises(Screenote::Deployment::ConfigurationError) do
        deployment(s3_environment(key => value), production: true)
      end
      assert_match message, error.message
    end
  end

  test "saas keeps every hosted provider fail fast" do
    error = assert_raises(Screenote::Deployment::ConfigurationError) do
      deployment(
        {
          "SCREENOTE_EDITION" => "saas",
          "SCREENOTE_BASE_URL" => "https://screenote.ai",
          "SECRET_KEY_BASE" => "a" * 64
        },
        production: true
      )
    end

    assert_match "SaaS configuration requires", error.message

    config = deployment(saas_environment, production: true)
    assert config.saas?
    assert config.billing?
    assert config.mail?
    assert config.monitoring?
    assert_equal %i[google_oauth2 github], config.social_oauth_providers
    assert_equal :rabata, config.active_storage_service
    assert_equal "operator@screenote.ai", config.saas_operator_email
  end

  test "SaaS operator identity must be explicit and normalized" do
    environment = saas_environment.except("SCREENOTE_SAAS_OPERATOR_EMAIL")
    error = assert_raises(Screenote::Deployment::ConfigurationError) do
      deployment(environment, production: true)
    end
    assert_includes error.message, "SCREENOTE_SAAS_OPERATOR_EMAIL"

    error = assert_raises(Screenote::Deployment::ConfigurationError) do
      deployment(
        saas_environment.merge("SCREENOTE_SAAS_OPERATOR_EMAIL" => "Operator@screenote.ai"),
        production: true
      )
    end
    assert_includes error.message, "normalized email"
  end

  test "secret values are redacted from inspection" do
    environment = self_hosted_environment(
      "SCREENOTE_SMTP_ENABLED" => "1",
      "SMTP_ADDRESS" => "smtp.example.test",
      "SMTP_PORT" => "587",
      "SMTP_USERNAME" => "screenote",
      "SMTP_PASSWORD" => "very-private-smtp-password",
      "MAILER_FROM" => "screenote@example.test"
    )

    inspected = deployment(environment, production: true).inspect

    assert_not_includes inspected, environment.fetch("SMTP_PASSWORD")
  end

  private

  def deployment(environment, production:)
    Screenote::Deployment.new(environment, production: production)
  end

  def self_hosted_environment(overrides = {})
    {
      "SCREENOTE_EDITION" => "self_hosted",
      "SCREENOTE_BASE_URL" => "http://screenote.internal:3000",
      "SECRET_KEY_BASE" => "a" * 64
    }.merge(overrides)
  end

  def native_once_environment(overrides = {})
    {
      "SCREENOTE_EDITION" => "self_hosted",
      "SECRET_KEY_BASE" => "a" * 64,
      "ONCE_HOST" => "screenote.example.test",
      "DISABLE_SSL" => "false"
    }.merge(overrides)
  end

  def s3_environment(overrides = {})
    self_hosted_environment.merge(
      "SCREENOTE_STORAGE" => "s3",
      "SCREENOTE_S3_ENDPOINT" => "https://objects.example.test",
      "SCREENOTE_S3_REGION" => "local",
      "SCREENOTE_S3_BUCKET" => "screenote-private",
      "SCREENOTE_S3_PREFIX" => "team-one",
      "SCREENOTE_S3_ACCESS_KEY_ID" => "access-key",
      "SCREENOTE_S3_SECRET_ACCESS_KEY" => "secret-key"
    ).merge(overrides)
  end

  def saas_environment
    {
      "SCREENOTE_EDITION" => "saas",
      "SCREENOTE_BASE_URL" => "https://screenote.ai",
      "SECRET_KEY_BASE" => "a" * 64,
      "DATABASE_URL" => "postgres://screenote:secret@db/screenote",
      "CACHE_DATABASE_URL" => "postgres://screenote:secret@db/screenote_cache",
      "QUEUE_DATABASE_URL" => "postgres://screenote:secret@db/screenote_queue",
      "CABLE_DATABASE_URL" => "postgres://screenote:secret@db/screenote_cable",
      "STRIPE_SECRET_KEY" => "stripe-secret",
      "STRIPE_WEBHOOK_SECRET" => "stripe-webhook-secret",
      "STRIPE_PRO_PRICE_ID" => "price_pro",
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
