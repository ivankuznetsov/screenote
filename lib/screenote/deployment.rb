# frozen_string_literal: true

require "digest"
require "ipaddr"
require "uri"

module Screenote
  class Deployment
    class ConfigurationError < StandardError; end

    EDITIONS = %w[saas self_hosted].freeze
    STORAGE_PROFILES = %w[local s3].freeze
    TRUE_VALUES = %w[1 true yes on].freeze
    FALSE_VALUES = %w[0 false no off].freeze
    DEFAULT_BASE_URLS = {
      saas: "https://screenote.ai",
      self_hosted: "http://localhost:3000"
    }.freeze
    SAAS_REQUIRED_KEYS = %w[
      DATABASE_URL
      CACHE_DATABASE_URL
      QUEUE_DATABASE_URL
      CABLE_DATABASE_URL
      STRIPE_SECRET_KEY
      STRIPE_WEBHOOK_SECRET
      STRIPE_PRO_PRICE_ID
      RESEND_API_KEY
      MAILER_FROM
      GOOGLE_CLIENT_ID
      GOOGLE_CLIENT_SECRET
      GITHUB_CLIENT_ID
      GITHUB_CLIENT_SECRET
      HONEYBADGER_API_KEY
      HONEYBADGER_JS_API_KEY
      RABATA_ENDPOINT
      RABATA_REGION
      RABATA_BUCKET
      RABATA_ACCESS_KEY_ID
      RABATA_SECRET_ACCESS_KEY
    ].freeze

    attr_reader :edition, :base_url, :host, :port, :trusted_proxies,
      :active_storage_service, :storage_namespace_fingerprint,
      :storage_configuration, :mail_configuration,
      :social_oauth_providers, :monitoring_configuration,
      :saas_operator_email

    class << self
      def configure!(environment = ENV, production: false)
        @current = new(environment, production: production)
      end

      def current
        @current || raise(ConfigurationError, "Screenote deployment has not been configured")
      end

      def reset!
        @current = nil
      end
    end

    def initialize(environment = ENV, production: false)
      @environment = environment
      @production = production
      @asset_build = truthy_without_validation?(value("SECRET_KEY_BASE_DUMMY"))

      configure_asset_build and return if asset_build?

      @edition = parse_edition
      validate_application_secret! if production?
      @base_uri = parse_origin(configured_base_url)
      @base_url = origin_for(@base_uri).freeze
      @host = @base_uri.host.freeze
      @port = @base_uri.port
      validate_once_ssl_compatibility! if self_hosted?
      @trusted_proxies = parse_trusted_proxies.freeze

      validate_saas_requirements! if production? && saas?
      configure_storage
      configure_mail
      configure_social_oauth
      configure_monitoring
      @saas_operator_email = configure_saas_operator_email
      @bootstrap_token_digest = digest_bootstrap_token

      @environment = nil
      freeze
    end

    def saas?
      edition == :saas
    end

    def self_hosted?
      edition == :self_hosted
    end

    def production?
      @production
    end

    def asset_build?
      @asset_build
    end

    def billing?
      saas?
    end

    def mail?
      mail_configuration.fetch(:provider) != :disabled
    end

    def monitoring?
      monitoring_configuration.fetch(:provider) != :disabled
    end

    def social_oauth?
      social_oauth_providers.any?
    end

    def social_oauth_configuration(provider)
      @social_oauth_configuration.fetch(provider.to_sym)
    end

    def force_ssl?
      @base_uri.scheme == "https"
    end

    alias_method :secure_cookies?, :force_ssl?

    def protocol
      @base_uri.scheme
    end

    def url_options
      options = { host: host, protocol: protocol }
      options[:port] = port unless default_port?
      options.freeze
    end

    def bootstrap_token_digest
      @bootstrap_token_digest
    end

    def inspect
      "#<#{self.class.name} edition=#{edition.inspect} base_url=#{base_url.inspect} " \
        "storage=#{active_storage_service.inspect} mail=#{mail?} social_oauth=#{social_oauth_providers.inspect} " \
        "monitoring=#{monitoring?}>"
    end

    private

    def configure_asset_build
      @edition = :saas
      @base_uri = URI.parse(DEFAULT_BASE_URLS.fetch(:saas))
      @base_url = DEFAULT_BASE_URLS.fetch(:saas)
      @host = @base_uri.host
      @port = @base_uri.port
      @trusted_proxies = [].freeze
      @active_storage_service = :local
      @storage_namespace_fingerprint = Digest::SHA256.hexdigest("local\0asset-build").freeze
      @storage_configuration = { root: "storage" }.freeze
      @mail_configuration = { provider: :disabled }.freeze
      @social_oauth_providers = [].freeze
      @social_oauth_configuration = {}.freeze
      @monitoring_configuration = { provider: :disabled }.freeze
      @saas_operator_email = nil
      @bootstrap_token_digest = nil
      @environment = nil
      freeze
    end

    def parse_edition
      raw = value("SCREENOTE_EDITION")
      raw = "saas" if raw.nil? && !production?

      unless EDITIONS.include?(raw)
        suffix = raw.nil? ? "is required in production" : "must be saas or self_hosted"
        raise ConfigurationError, "SCREENOTE_EDITION #{suffix}"
      end

      raw.to_sym
    end

    def parse_origin(raw)
      uri = URI.parse(raw)
      valid_path = uri.path.nil? || uri.path.empty? || uri.path == "/"
      valid = uri.is_a?(URI::HTTP) && %w[http https].include?(uri.scheme) &&
        !blank?(uri.host) && uri.userinfo.nil? && valid_path &&
        uri.query.nil? && uri.fragment.nil?

      raise ConfigurationError, "SCREENOTE_BASE_URL must be one HTTP(S) origin without credentials, path, query, or fragment" unless valid

      uri
    rescue URI::InvalidURIError, URI::InvalidComponentError
      raise ConfigurationError, "SCREENOTE_BASE_URL must be a valid HTTP(S) origin"
    end

    def origin_for(uri)
      authority = uri.hostname
      authority = "[#{authority}]" if authority.include?(":")
      authority = "#{authority}:#{uri.port}" unless default_port_for?(uri)
      "#{uri.scheme}://#{authority}"
    end

    def default_base_url
      "http://localhost:3000"
    end

    def configured_base_url
      configured = value("SCREENOTE_BASE_URL")
      return configured unless configured.nil?
      return default_base_url unless production?

      raise ConfigurationError, "SCREENOTE_BASE_URL is required in production"
    end

    def validate_application_secret!
      secret = value("SECRET_KEY_BASE")
      return if secret && secret.bytesize >= 32

      raise ConfigurationError, "SECRET_KEY_BASE must contain at least 32 bytes in production"
    end

    def validate_once_ssl_compatibility!
      return unless @environment.key?("DISABLE_SSL")

      disable_ssl = boolean("DISABLE_SSL", default: false)
      return if disable_ssl == !force_ssl?

      raise ConfigurationError,
        "DISABLE_SSL must be true exactly when SCREENOTE_BASE_URL uses http"
    end

    def default_port?
      default_port_for?(@base_uri)
    end

    def default_port_for?(uri)
      (uri.scheme == "http" && uri.port == 80) || (uri.scheme == "https" && uri.port == 443)
    end

    def parse_trusted_proxies
      value("SCREENOTE_TRUSTED_PROXIES").to_s.split(",").filter_map do |entry|
        next if entry.strip.empty?

        proxy = IPAddr.new(entry.strip)
        if proxy.prefix.zero?
          raise ConfigurationError, "SCREENOTE_TRUSTED_PROXIES cannot trust the entire internet"
        end

        proxy.freeze
      rescue IPAddr::InvalidAddressError
        raise ConfigurationError, "SCREENOTE_TRUSTED_PROXIES must contain only comma-separated IP addresses or CIDRs"
      end
    end

    def validate_saas_requirements!
      missing = SAAS_REQUIRED_KEYS.select { |key| blank?(value(key)) }
      return if missing.empty?

      raise ConfigurationError, "SaaS configuration requires: #{missing.join(', ')}"
    end

    def configure_storage
      if saas?
        validate_provider_endpoint!("RABATA_ENDPOINT") if production?
        @active_storage_service = :rabata
        @storage_configuration = compact_frozen_hash(
          endpoint: value("RABATA_ENDPOINT"),
          region: value("RABATA_REGION"),
          bucket: value("RABATA_BUCKET"),
          access_key_id: value("RABATA_ACCESS_KEY_ID"),
          secret_access_key: value("RABATA_SECRET_ACCESS_KEY"),
          force_path_style: true
        )
        namespace = [
          "rabata",
          value("RABATA_ENDPOINT"),
          value("RABATA_REGION"),
          value("RABATA_BUCKET")
        ]
      else
        profile = value("SCREENOTE_STORAGE") || "local"
        unless STORAGE_PROFILES.include?(profile)
          raise ConfigurationError, "SCREENOTE_STORAGE must be local or s3"
        end

        if profile == "local"
          @active_storage_service = :self_hosted_local
          @storage_configuration = { root: "/rails/storage/blobs" }.freeze
          namespace = [ "self_hosted_local", "/rails/storage/blobs" ]
        else
          required = %w[
            SCREENOTE_S3_ENDPOINT
            SCREENOTE_S3_REGION
            SCREENOTE_S3_BUCKET
            SCREENOTE_S3_PREFIX
            SCREENOTE_S3_ACCESS_KEY_ID
            SCREENOTE_S3_SECRET_ACCESS_KEY
          ]
          require_selected_provider!("S3 storage", required)
          validate_provider_endpoint!("SCREENOTE_S3_ENDPOINT")
          validate_storage_prefix!
          path_style = boolean("SCREENOTE_S3_PATH_STYLE", default: true)
          @active_storage_service = :self_hosted_s3
          @storage_configuration = compact_frozen_hash(
            endpoint: value("SCREENOTE_S3_ENDPOINT"),
            region: value("SCREENOTE_S3_REGION"),
            bucket: value("SCREENOTE_S3_BUCKET"),
            prefix: value("SCREENOTE_S3_PREFIX"),
            access_key_id: value("SCREENOTE_S3_ACCESS_KEY_ID"),
            secret_access_key: value("SCREENOTE_S3_SECRET_ACCESS_KEY"),
            force_path_style: path_style,
            request_timeout: positive_integer("SCREENOTE_S3_REQUEST_TIMEOUT", default: 30),
            retry_limit: nonnegative_integer("SCREENOTE_S3_RETRY_LIMIT", default: 3)
          )
          namespace = [
            "self_hosted_s3",
            value("SCREENOTE_S3_ENDPOINT"),
            value("SCREENOTE_S3_REGION"),
            value("SCREENOTE_S3_BUCKET"),
            value("SCREENOTE_S3_PREFIX"),
            path_style
          ]
        end
      end

      @storage_namespace_fingerprint = Digest::SHA256.hexdigest(namespace.join("\0")).freeze
    end

    def configure_mail
      if saas?
        @mail_configuration = compact_frozen_hash(
          provider: :resend,
          api_key: value("RESEND_API_KEY"),
          from: value("MAILER_FROM")
        )
        return
      end

      unless self_hosted_smtp_enabled?
        @mail_configuration = { provider: :disabled }.freeze
        return
      end

      mailer_from = value("MAILER_FROM") || value("MAILER_FROM_ADDRESS")
      required = %w[SMTP_ADDRESS SMTP_PORT SMTP_USERNAME SMTP_PASSWORD]
      missing = required.select { |key| blank?(value(key)) }
      missing << "MAILER_FROM or MAILER_FROM_ADDRESS" if blank?(mailer_from)
      unless missing.empty?
        raise ConfigurationError, "Selected SMTP provider requires: #{missing.join(', ')}"
      end

      @mail_configuration = compact_frozen_hash(
        provider: :smtp,
        address: value("SMTP_ADDRESS"),
        port: positive_integer("SMTP_PORT"),
        user_name: value("SMTP_USERNAME"),
        password: value("SMTP_PASSWORD"),
        from: mailer_from,
        domain: value("SMTP_DOMAIN") || host,
        authentication: (value("SMTP_AUTHENTICATION") || "plain").to_sym,
        enable_starttls_auto: boolean("SMTP_STARTTLS", default: true)
      )
    end

    def self_hosted_smtp_enabled?
      if @environment.key?("SCREENOTE_SMTP_ENABLED")
        boolean("SCREENOTE_SMTP_ENABLED", default: false)
      else
        !blank?(value("SMTP_ADDRESS"))
      end
    end

    def configure_social_oauth
      providers = []
      configurations = {}

      configure_oauth_provider(
        providers,
        configurations,
        provider: :google_oauth2,
        enabled: saas? || boolean("SCREENOTE_GOOGLE_OAUTH_ENABLED", default: false),
        id_key: "GOOGLE_CLIENT_ID",
        secret_key: "GOOGLE_CLIENT_SECRET"
      )
      configure_oauth_provider(
        providers,
        configurations,
        provider: :github,
        enabled: saas? || boolean("SCREENOTE_GITHUB_OAUTH_ENABLED", default: false),
        id_key: "GITHUB_CLIENT_ID",
        secret_key: "GITHUB_CLIENT_SECRET"
      )

      @social_oauth_providers = providers.freeze
      @social_oauth_configuration = configurations.freeze
    end

    def configure_oauth_provider(providers, configurations, provider:, enabled:, id_key:, secret_key:)
      return unless enabled

      require_selected_provider!(provider.to_s, [ id_key, secret_key ]) unless saas? && !production?
      providers << provider
      configurations[provider] = {
        client_id: value(id_key),
        client_secret: value(secret_key)
      }.freeze
    end

    def configure_monitoring
      enabled = saas? || boolean("SCREENOTE_HONEYBADGER_ENABLED", default: false)
      unless enabled
        @monitoring_configuration = { provider: :disabled }.freeze
        return
      end

      required = [ "HONEYBADGER_API_KEY" ]
      required << "HONEYBADGER_JS_API_KEY" if saas?
      require_selected_provider!("Honeybadger", required) unless saas? && !production?
      @monitoring_configuration = compact_frozen_hash(
        provider: :honeybadger,
        api_key: value("HONEYBADGER_API_KEY"),
        javascript_api_key: saas? ? value("HONEYBADGER_JS_API_KEY") : nil,
        insights: saas?
      )
    end

    def configure_saas_operator_email
      return unless saas?

      email = value("SCREENOTE_SAAS_OPERATOR_EMAIL") || ("admin@example.com" unless production?)
      unless email&.match?(URI::MailTo::EMAIL_REGEXP) && email == email.downcase
        raise ConfigurationError, "SCREENOTE_SAAS_OPERATOR_EMAIL must be a normalized email address"
      end

      email.freeze
    end

    def digest_bootstrap_token
      return unless self_hosted?

      token = value("SCREENOTE_BOOTSTRAP_TOKEN")
      return if blank?(token)

      if token.bytesize < 32 || token.match?(/\s/)
        raise ConfigurationError, "SCREENOTE_BOOTSTRAP_TOKEN must contain at least 32 non-whitespace bytes"
      end

      Digest::SHA256.hexdigest(token).freeze
    end

    def validate_provider_endpoint!(key)
      uri = URI.parse(value(key))
      root_path = uri.path.nil? || uri.path.empty? || uri.path == "/"
      valid = uri.is_a?(URI::HTTP) && %w[http https].include?(uri.scheme) &&
        !blank?(uri.host) && uri.userinfo.nil? && root_path &&
        uri.query.nil? && uri.fragment.nil?
      return if valid

      raise ConfigurationError,
        "#{key} must be one HTTP(S) endpoint without credentials, path, query, or fragment"
    rescue URI::InvalidURIError, URI::InvalidComponentError
      raise ConfigurationError, "#{key} must be a valid HTTP(S) endpoint"
    end

    def validate_storage_prefix!
      prefix = value("SCREENOTE_S3_PREFIX")
      segments = prefix.to_s.split("/", -1)
      valid = prefix && prefix.bytesize <= 256 && segments.all? do |segment|
        segment.match?(/\A[A-Za-z0-9][A-Za-z0-9._-]{0,62}\z/) && !%w[. ..].include?(segment)
      end
      return if valid

      raise ConfigurationError,
        "SCREENOTE_S3_PREFIX must be a slash-separated object namespace without empty, dot, or parent segments"
    end

    def require_selected_provider!(name, keys)
      missing = keys.select { |key| blank?(value(key)) }
      return if missing.empty?

      raise ConfigurationError, "Selected #{name} provider requires: #{missing.join(', ')}"
    end

    def boolean(key, default:)
      raw = value(key)
      return default if raw.nil?

      normalized = raw.downcase
      return true if TRUE_VALUES.include?(normalized)
      return false if FALSE_VALUES.include?(normalized)

      raise ConfigurationError, "#{key} must be true or false"
    end

    def positive_integer(key, default: nil)
      integer = integer_value(key, default: default)
      raise ConfigurationError, "#{key} must be a positive integer" unless integer&.positive?

      integer
    end

    def nonnegative_integer(key, default: nil)
      integer = integer_value(key, default: default)
      raise ConfigurationError, "#{key} must be a non-negative integer" unless integer && integer >= 0

      integer
    end

    def integer_value(key, default:)
      raw = value(key)
      return default if raw.nil?

      Integer(raw, 10)
    rescue ArgumentError
      nil
    end

    def compact_frozen_hash(values)
      values.compact.freeze
    end

    def value(key)
      raw = @environment[key]
      return if raw.nil?

      stripped = raw.to_s.strip
      stripped unless stripped.empty?
    end

    def blank?(value)
      value.nil? || value.empty?
    end

    def truthy_without_validation?(raw)
      TRUE_VALUES.include?(raw.to_s.downcase)
    end
  end
end
