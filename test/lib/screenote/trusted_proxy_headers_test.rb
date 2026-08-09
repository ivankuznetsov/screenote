# frozen_string_literal: true

# screenote-edition: self_hosted

require "test_helper"

class Screenote::TrustedProxyHeadersTest < ActiveSupport::TestCase
  test "untrusted peers cannot supply forwarded client or origin identity" do
    captured = nil
    middleware = middleware_for([]) { |environment| captured = environment.dup }

    middleware.call(forwarded_environment("REMOTE_ADDR" => "203.0.113.10"))

    Screenote::TrustedProxyHeaders::FORWARDED_HEADERS.each do |header|
      assert_not captured.key?(header), header
    end
  end

  test "a trusted ONCE chain discards a supplied prefix and uses the canonical HTTP scheme" do
    captured = nil
    proxies = [ IPAddr.new("127.0.0.1/32") ]
    terminal = lambda do |environment|
      captured = environment.dup
      request = ActionDispatch::Request.new(environment)
      [ 200, {}, [ "#{request.remote_ip}|#{request.scheme}" ] ]
    end
    remote_ip = ActionDispatch::RemoteIp.new(terminal, true, proxies)
    middleware = Screenote::TrustedProxyHeaders.new(
      remote_ip,
      trusted_proxies: proxies,
      forwarded_client_hops: 2,
      canonical_scheme: "http",
      forwarded_proxy_host: "once-proxy",
      address_resolver: ->(_host) { [ "192.168.192.2" ] }
    )

    _status, _headers, body = middleware.call(
      forwarded_environment(
        "REMOTE_ADDR" => "127.0.0.1",
        "HTTP_X_FORWARDED_FOR" => "203.0.113.99, 198.51.100.77, 192.168.192.2",
        "rack.url_scheme" => "http"
      )
    )

    assert_equal [ "198.51.100.77|http" ], body
    assert_equal "198.51.100.77", captured.fetch("REMOTE_ADDR")
    assert_equal "http", captured.fetch("rack.url_scheme")
    Screenote::TrustedProxyHeaders::FORWARDED_HEADERS.each do |header|
      assert_not captured.key?(header), header
    end
  end

  test "an invalid immediate peer address is never trusted" do
    captured = nil
    middleware = middleware_for([ IPAddr.new("10.0.0.0/8") ]) { |environment| captured = environment.dup }

    middleware.call(forwarded_environment("REMOTE_ADDR" => "not-an-address"))

    assert_not captured.key?("HTTP_X_FORWARDED_FOR")
  end

  test "untrusted forwarding cannot change Rails client IP or Rack scheme" do
    terminal = lambda do |environment|
      request = ActionDispatch::Request.new(environment)
      [ 200, {}, [ "#{request.remote_ip}|#{request.scheme}" ] ]
    end
    remote_ip = ActionDispatch::RemoteIp.new(terminal, true, [])
    middleware = Screenote::TrustedProxyHeaders.new(
      remote_ip,
      trusted_proxies: [],
      forwarded_client_hops: 1,
      canonical_scheme: "https",
      forwarded_proxy_host: nil
    )
    environment = forwarded_environment(
      "REMOTE_ADDR" => "203.0.113.10",
      "rack.url_scheme" => "http"
    )

    _status, _headers, body = middleware.call(environment)

    assert_equal [ "203.0.113.10|http" ], body
  end

  test "the canonical HTTPS origin overrides forwarded transport headers" do
    proxies = [ IPAddr.new("127.0.0.1/32") ]
    terminal = lambda do |environment|
      request = ActionDispatch::Request.new(environment)
      [ 200, {}, [ "#{request.remote_ip}|#{request.scheme}" ] ]
    end
    remote_ip = ActionDispatch::RemoteIp.new(terminal, true, proxies)
    middleware = Screenote::TrustedProxyHeaders.new(
      remote_ip,
      trusted_proxies: proxies,
      forwarded_client_hops: 2,
      canonical_scheme: "https",
      forwarded_proxy_host: "once-proxy",
      address_resolver: ->(_host) { [ "192.168.192.2" ] }
    )
    environment = forwarded_environment(
      "REMOTE_ADDR" => "127.0.0.1",
      "HTTP_X_FORWARDED_FOR" => "198.51.100.77, 192.168.192.2",
      "HTTP_X_FORWARDED_PROTO" => "http",
      "HTTP_X_FORWARDED_SSL" => "off",
      "rack.url_scheme" => "http"
    )

    _status, _headers, body = middleware.call(environment)

    assert_equal [ "198.51.100.77|https" ], body
  end

  test "the canonical HTTP origin removes an inherited HTTPS gateway value" do
    captured = nil
    middleware = middleware_for([ IPAddr.new("127.0.0.1/32") ]) do |environment|
      captured = environment.dup
    end

    middleware.call(
      forwarded_environment(
        "REMOTE_ADDR" => "127.0.0.1",
        "HTTPS" => "on",
        "rack.url_scheme" => "https"
      )
    )

    assert_equal "http", ActionDispatch::Request.new(captured).scheme
    assert_not captured.key?("HTTPS")
  end

  test "a direct Thruster chain takes the last address regardless of a supplied prefix" do
    proxies = [ IPAddr.new("127.0.0.1/32") ]
    terminal = lambda do |environment|
      request = ActionDispatch::Request.new(environment)
      [ 200, {}, [ "#{request.remote_ip}|#{request.scheme}" ] ]
    end
    remote_ip = ActionDispatch::RemoteIp.new(terminal, true, proxies)
    middleware = Screenote::TrustedProxyHeaders.new(
      remote_ip,
      trusted_proxies: proxies,
      forwarded_client_hops: 1,
      canonical_scheme: "http",
      forwarded_proxy_host: nil
    )
    environment = forwarded_environment(
      "REMOTE_ADDR" => "127.0.0.1",
      "HTTP_X_FORWARDED_FOR" => "203.0.113.99, 198.51.100.77",
      "rack.url_scheme" => "http"
    )

    _status, _headers, body = middleware.call(environment)

    assert_equal [ "198.51.100.77|http" ], body
  end

  test "a direct one-address chain is retained while a malformed proxy chain falls back" do
    proxies = [ IPAddr.new("127.0.0.1/32") ]
    terminal = lambda do |environment|
      request = ActionDispatch::Request.new(environment)
      [ 200, {}, [ "#{request.remote_ip}|#{request.scheme}" ] ]
    end
    remote_ip = ActionDispatch::RemoteIp.new(terminal, true, proxies)
    middleware = Screenote::TrustedProxyHeaders.new(
      remote_ip,
      trusted_proxies: proxies,
      forwarded_client_hops: 2,
      canonical_scheme: "http",
      forwarded_proxy_host: "once-proxy",
      address_resolver: ->(_host) { [ "192.168.192.2" ] }
    )

    short = forwarded_environment(
      "REMOTE_ADDR" => "127.0.0.1",
      "HTTP_X_FORWARDED_FOR" => "198.51.100.77",
      "rack.url_scheme" => "http"
    )
    malformed = forwarded_environment(
      "REMOTE_ADDR" => "127.0.0.1",
      "HTTP_X_FORWARDED_FOR" => "not-an-address, 192.168.192.2",
      "rack.url_scheme" => "http"
    )

    assert_equal [ "198.51.100.77|http" ], middleware.call(short).last
    assert_equal [ "127.0.0.1|http" ], middleware.call(malformed).last
  end

  test "a sibling that bypasses the configured proxy cannot supply the promoted client" do
    proxies = [ IPAddr.new("127.0.0.1/32") ]
    terminal = lambda do |environment|
      request = ActionDispatch::Request.new(environment)
      [ 200, {}, [ "#{request.remote_ip}|#{request.scheme}" ] ]
    end
    remote_ip = ActionDispatch::RemoteIp.new(terminal, true, proxies)
    middleware = Screenote::TrustedProxyHeaders.new(
      remote_ip,
      trusted_proxies: proxies,
      forwarded_client_hops: 2,
      canonical_scheme: "http",
      forwarded_proxy_host: "once-proxy",
      address_resolver: ->(_host) { [ "192.168.192.2" ] }
    )
    environment = forwarded_environment(
      "REMOTE_ADDR" => "127.0.0.1",
      "HTTP_X_FORWARDED_FOR" => "203.0.113.99, 192.168.192.8",
      "rack.url_scheme" => "http"
    )

    _status, _headers, body = middleware.call(environment)

    assert_equal [ "192.168.192.8|http" ], body
  end

  test "proxy identity is refreshed after its address changes" do
    now = 0
    resolutions = [ [ "192.168.192.2" ], [ "192.168.192.9" ] ]
    middleware = two_hop_middleware(
      address_resolver: ->(_host) { resolutions.shift },
      monotonic_clock: -> { now }
    )
    now = Screenote::TrustedProxyHeaders::PROXY_ADDRESS_TTL

    _status, _headers, body = middleware.call(
      forwarded_environment(
        "REMOTE_ADDR" => "127.0.0.1",
        "HTTP_X_FORWARDED_FOR" => "198.51.100.77, 192.168.192.9"
      )
    )

    assert_equal [ "198.51.100.77|http" ], body
  end

  test "a stale proxy address cannot authenticate a sibling after DNS changes" do
    now = 0
    resolutions = [ [ "192.168.192.2" ], [ "192.168.192.9" ] ]
    middleware = two_hop_middleware(
      address_resolver: ->(_host) { resolutions.shift },
      monotonic_clock: -> { now }
    )
    now = Screenote::TrustedProxyHeaders::PROXY_ADDRESS_TTL

    _status, _headers, body = middleware.call(
      forwarded_environment(
        "REMOTE_ADDR" => "127.0.0.1",
        "HTTP_X_FORWARDED_FOR" => "203.0.113.99, 192.168.192.2"
      )
    )

    assert_equal [ "192.168.192.2|http" ], body
  end

  test "a request fails safely when proxy DNS becomes unavailable" do
    now = 0
    resolution_count = 0
    middleware = two_hop_middleware(
      address_resolver: lambda do |_host|
        resolution_count += 1
        raise SocketError if resolution_count > 1

        [ "192.168.192.2" ]
      end,
      monotonic_clock: -> { now }
    )
    now = Screenote::TrustedProxyHeaders::PROXY_ADDRESS_TTL

    environment = lambda do
      forwarded_environment(
        "REMOTE_ADDR" => "127.0.0.1",
        "HTTP_X_FORWARDED_FOR" => "198.51.100.77, 192.168.192.2"
      )
    end
    _status, _headers, body = middleware.call(environment.call)
    _status, _headers, repeated_body = middleware.call(environment.call)

    assert_equal [ "192.168.192.2|http" ], body
    assert_equal [ "192.168.192.2|http" ], repeated_body
    assert_equal 2, resolution_count
  end

  test "an IPv6 proxy chain promotes its normalized client address" do
    middleware = two_hop_middleware(address_resolver: ->(_host) { [ "fd00::2" ] })

    _status, _headers, body = middleware.call(
      forwarded_environment(
        "REMOTE_ADDR" => "127.0.0.1",
        "HTTP_X_FORWARDED_FOR" => "2001:db8::77, fd00::2"
      )
    )

    assert_equal [ "2001:db8::77|http" ], body
  end

  test "constructor rejects an invalid proxy chain contract" do
    terminal = ->(_environment) { [ 200, {}, [] ] }

    assert_raises(ArgumentError) do
      Screenote::TrustedProxyHeaders.new(
        terminal,
        trusted_proxies: [],
        forwarded_client_hops: 0,
        canonical_scheme: "http",
        forwarded_proxy_host: nil
      )
    end
    assert_raises(ArgumentError) do
      Screenote::TrustedProxyHeaders.new(
        terminal,
        trusted_proxies: [],
        forwarded_client_hops: 1,
        canonical_scheme: "ftp",
        forwarded_proxy_host: nil
      )
    end
    assert_raises(ArgumentError) do
      Screenote::TrustedProxyHeaders.new(
        terminal,
        trusted_proxies: [],
        forwarded_client_hops: 3,
        canonical_scheme: "http",
        forwarded_proxy_host: "proxy"
      )
    end
    error = assert_raises(ArgumentError) do
      Screenote::TrustedProxyHeaders.new(
        terminal,
        trusted_proxies: [],
        forwarded_client_hops: 2,
        canonical_scheme: "http",
        forwarded_proxy_host: "missing-proxy",
        address_resolver: ->(_host) { [] }
      )
    end
    assert_equal "forwarded_proxy_host must resolve to at least one IP address", error.message

    [ SocketError, Resolv::ResolvTimeout ].each do |resolver_error|
      error = assert_raises(ArgumentError) do
        Screenote::TrustedProxyHeaders.new(
          terminal,
          trusted_proxies: [],
          forwarded_client_hops: 2,
          canonical_scheme: "http",
          forwarded_proxy_host: "missing-proxy",
          address_resolver: ->(_host) { raise resolver_error }
        )
      end
      assert_equal "forwarded_proxy_host must resolve to at least one IP address", error.message
    end
  end

  test "the default DNS resolver has a finite timeout" do
    fake_resolver = Struct.new(:timeouts, :closed) do
      def getaddresses(_host)
        [ IPAddr.new("192.168.192.2") ]
      end

      def close
        self.closed = true
      end
    end.new
    middleware = middleware_for([]) { |_environment| }

    addresses = middleware.send(:resolve_dns_addresses, "proxy.invalid", resolver: fake_resolver)

    assert_equal Screenote::TrustedProxyHeaders::DNS_RESOLUTION_TIMEOUT, fake_resolver.timeouts
    assert_equal [ "192.168.192.2" ], addresses
    assert_predicate fake_resolver, :closed
  end

  private

  def middleware_for(proxies, forwarded_client_hops: 1, canonical_scheme: "http", &capture)
    terminal = lambda do |environment|
      capture.call(environment)
      [ 200, {}, [] ]
    end
    Screenote::TrustedProxyHeaders.new(
      terminal,
      trusted_proxies: proxies,
      forwarded_client_hops: forwarded_client_hops,
      canonical_scheme: canonical_scheme,
      forwarded_proxy_host: nil
    )
  end

  def two_hop_middleware(address_resolver:, monotonic_clock: -> { 0 })
    proxies = [ IPAddr.new("127.0.0.1/32") ]
    terminal = lambda do |environment|
      request = ActionDispatch::Request.new(environment)
      [ 200, {}, [ "#{request.remote_ip}|#{request.scheme}" ] ]
    end
    remote_ip = ActionDispatch::RemoteIp.new(terminal, true, proxies)
    Screenote::TrustedProxyHeaders.new(
      remote_ip,
      trusted_proxies: proxies,
      forwarded_client_hops: 2,
      canonical_scheme: "http",
      forwarded_proxy_host: "once-proxy",
      address_resolver: address_resolver,
      monotonic_clock: monotonic_clock
    )
  end

  def forwarded_environment(overrides = {})
    {
      "HTTP_FORWARDED" => "for=198.51.100.77;proto=https",
      "HTTP_X_FORWARDED_FOR" => "198.51.100.77",
      "HTTP_X_FORWARDED_HOST" => "notes.example.test",
      "HTTP_X_FORWARDED_PORT" => "443",
      "HTTP_X_FORWARDED_PROTO" => "https",
      "HTTP_X_FORWARDED_SCHEME" => "https",
      "HTTP_X_FORWARDED_SSL" => "on",
      "HTTP_X_REAL_IP" => "198.51.100.77",
      "HTTP_CLIENT_IP" => "198.51.100.77",
      "HTTP_CF_CONNECTING_IP" => "198.51.100.77"
    }.merge(overrides)
  end
end
