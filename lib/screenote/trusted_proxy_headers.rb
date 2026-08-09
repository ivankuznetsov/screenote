# frozen_string_literal: true

require "ipaddr"
require "resolv"

module Screenote
  # Rack does not authenticate Forwarded or X-Forwarded-* headers. A trusted
  # proxy chain appends its addresses to X-Forwarded-For, so select the client
  # by its position from the right, then discard every forwarded header before
  # Rails derives request identity. The canonical deployment origin, rather
  # than a caller-controlled header, supplies the public request scheme.
  class TrustedProxyHeaders
    DNS_RESOLUTION_TIMEOUT = 0.25
    PROXY_ADDRESS_TTL = 1

    FORWARDED_HEADERS = %w[
      HTTP_FORWARDED
      HTTP_X_FORWARDED_FOR
      HTTP_X_FORWARDED_HOST
      HTTP_X_FORWARDED_PORT
      HTTP_X_FORWARDED_PROTO
      HTTP_X_FORWARDED_SCHEME
      HTTP_X_FORWARDED_SSL
      HTTP_X_REAL_IP
      HTTP_CLIENT_IP
      HTTP_CF_CONNECTING_IP
    ].freeze

    def initialize(
      app,
      trusted_proxies:,
      forwarded_client_hops:,
      canonical_scheme:,
      forwarded_proxy_host:,
      address_resolver: method(:resolve_addresses),
      monotonic_clock: -> { Process.clock_gettime(Process::CLOCK_MONOTONIC) }
    )
      unless [ 1, 2 ].include?(forwarded_client_hops)
        raise ArgumentError, "forwarded_client_hops must be 1 or 2"
      end
      raise ArgumentError, "canonical_scheme must be http or https" unless %w[http https].include?(canonical_scheme)

      @app = app
      @trusted_proxies = trusted_proxies
      @forwarded_client_hops = forwarded_client_hops
      @canonical_scheme = canonical_scheme
      @forwarded_proxy_host = forwarded_proxy_host
      @address_resolver = address_resolver
      @monotonic_clock = monotonic_clock
      @proxy_address_mutex = Mutex.new
      @forwarded_proxy_addresses = [].freeze
      @forwarded_proxy_addresses_expires_at = 0.0
      validate_forwarded_proxy!
    end

    def call(environment)
      if trusted_peer?(environment["REMOTE_ADDR"])
        promote_forwarded_client(environment)
        apply_canonical_scheme(environment)
      end
      strip_forwarded_headers(environment)
      @app.call(environment)
    end

    private

    attr_reader :address_resolver, :canonical_scheme, :forwarded_client_hops, :forwarded_proxy_host,
      :monotonic_clock, :trusted_proxies

    def resolve_addresses(host)
      literal_address = normalized_address(host)
      return [ literal_address ] if literal_address

      hosts_addresses = Resolv::Hosts.new.getaddresses(host).map(&:to_s)
      return hosts_addresses unless hosts_addresses.empty?

      resolve_dns_addresses(host)
    end

    def resolve_dns_addresses(host, resolver: Resolv::DNS.new)
      resolver.timeouts = DNS_RESOLUTION_TIMEOUT
      resolver.getaddresses(host).map(&:to_s)
    ensure
      resolver.close
    end

    def validate_forwarded_proxy!
      return if forwarded_client_hops == 1
      raise ArgumentError, "forwarded_proxy_host is required for a two-hop proxy chain" if forwarded_proxy_host.to_s.empty?

      refresh_forwarded_proxy_addresses
      return unless @forwarded_proxy_addresses.empty?

      raise ArgumentError, "forwarded_proxy_host must resolve to at least one IP address"
    end

    def forwarded_proxy_addresses
      return @forwarded_proxy_addresses if proxy_addresses_fresh?

      @proxy_address_mutex.synchronize do
        refresh_forwarded_proxy_addresses unless proxy_addresses_fresh?
        @forwarded_proxy_addresses
      end
    end

    def refresh_forwarded_proxy_addresses
      @forwarded_proxy_addresses = resolved_forwarded_proxy_addresses.freeze
      @forwarded_proxy_addresses_expires_at = monotonic_clock.call + PROXY_ADDRESS_TTL
    end

    def resolved_forwarded_proxy_addresses
      address_resolver.call(forwarded_proxy_host).filter_map { |address| normalized_address(address) }.uniq
    rescue SocketError, Resolv::ResolvError, Resolv::ResolvTimeout
      []
    end

    def proxy_addresses_fresh?
      monotonic_clock.call < @forwarded_proxy_addresses_expires_at
    end

    def trusted_peer?(remote_address)
      address = IPAddr.new(remote_address.to_s)
      trusted_proxies.any? { |proxy| proxy.include?(address) }
    rescue IPAddr::InvalidAddressError
      false
    end

    def strip_forwarded_headers(environment)
      FORWARDED_HEADERS.each { |header| environment.delete(header) }
    end

    def promote_forwarded_client(environment)
      addresses = environment["HTTP_X_FORWARDED_FOR"].to_s.split(",").map(&:strip)
      upstream_peer = normalized_address(addresses.last)
      return if upstream_peer.nil?

      candidate = if forwarded_client_hops == 2 && forwarded_proxy_addresses.include?(upstream_peer)
        normalized_address(addresses[-2])
      else
        upstream_peer
      end
      environment["REMOTE_ADDR"] = candidate if candidate
    end

    def normalized_address(value)
      address = IPAddr.new(value.to_s)
      range = address.to_range
      return unless range.begin == range.end

      address.to_s
    rescue IPAddr::InvalidAddressError
      nil
    end

    def apply_canonical_scheme(environment)
      environment["rack.url_scheme"] = canonical_scheme
      if canonical_scheme == "https"
        environment["HTTPS"] = "on"
      else
        environment.delete("HTTPS")
      end
    end
  end
end
