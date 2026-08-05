# frozen_string_literal: true

require "ipaddr"

module Screenote
  # Rack does not authenticate Forwarded or X-Forwarded-* headers. Strip them
  # before Rails derives the client IP or request scheme unless the immediate
  # peer is an explicitly configured reverse proxy.
  class TrustedProxyHeaders
    FORWARDED_HEADERS = %w[
      HTTP_FORWARDED
      HTTP_X_FORWARDED_FOR
      HTTP_X_FORWARDED_HOST
      HTTP_X_FORWARDED_PORT
      HTTP_X_FORWARDED_PROTO
      HTTP_X_FORWARDED_SSL
      HTTP_X_REAL_IP
      HTTP_CLIENT_IP
      HTTP_CF_CONNECTING_IP
    ].freeze

    def initialize(app, trusted_proxies:)
      @app = app
      @trusted_proxies = trusted_proxies
    end

    def call(environment)
      strip_forwarded_headers(environment) unless trusted_peer?(environment["REMOTE_ADDR"])
      @app.call(environment)
    end

    private

    attr_reader :trusted_proxies

    def trusted_peer?(remote_address)
      address = IPAddr.new(remote_address.to_s)
      trusted_proxies.any? { |proxy| proxy.include?(address) }
    rescue IPAddr::InvalidAddressError
      false
    end

    def strip_forwarded_headers(environment)
      FORWARDED_HEADERS.each { |header| environment.delete(header) }
    end
  end
end
