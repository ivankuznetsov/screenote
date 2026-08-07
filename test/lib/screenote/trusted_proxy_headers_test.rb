# frozen_string_literal: true

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

  test "an explicitly trusted immediate peer retains forwarded headers" do
    captured = nil
    middleware = middleware_for([ IPAddr.new("10.0.0.0/8") ]) { |environment| captured = environment.dup }

    middleware.call(forwarded_environment("REMOTE_ADDR" => "10.2.3.4"))

    assert_equal "198.51.100.77", captured.fetch("HTTP_X_FORWARDED_FOR")
    assert_equal "https", captured.fetch("HTTP_X_FORWARDED_PROTO")
    assert_equal "notes.example.test", captured.fetch("HTTP_X_FORWARDED_HOST")
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
    middleware = Screenote::TrustedProxyHeaders.new(remote_ip, trusted_proxies: [])
    environment = forwarded_environment(
      "REMOTE_ADDR" => "203.0.113.10",
      "rack.url_scheme" => "http"
    )

    _status, _headers, body = middleware.call(environment)

    assert_equal [ "203.0.113.10|http" ], body
  end

  test "trusted forwarding drives Rails client IP and scheme" do
    proxies = [ IPAddr.new("10.0.0.0/8") ]
    terminal = lambda do |environment|
      request = ActionDispatch::Request.new(environment)
      [ 200, {}, [ "#{request.remote_ip}|#{request.scheme}" ] ]
    end
    remote_ip = ActionDispatch::RemoteIp.new(terminal, true, proxies)
    middleware = Screenote::TrustedProxyHeaders.new(remote_ip, trusted_proxies: proxies)
    environment = forwarded_environment(
      "REMOTE_ADDR" => "10.2.3.4",
      "rack.url_scheme" => "http"
    )

    _status, _headers, body = middleware.call(environment)

    assert_equal [ "198.51.100.77|https" ], body
  end

  private

  def middleware_for(proxies, &capture)
    terminal = lambda do |environment|
      capture.call(environment)
      [ 200, {}, [] ]
    end
    Screenote::TrustedProxyHeaders.new(terminal, trusted_proxies: proxies)
  end

  def forwarded_environment(overrides = {})
    {
      "HTTP_FORWARDED" => "for=198.51.100.77;proto=https",
      "HTTP_X_FORWARDED_FOR" => "198.51.100.77",
      "HTTP_X_FORWARDED_HOST" => "notes.example.test",
      "HTTP_X_FORWARDED_PORT" => "443",
      "HTTP_X_FORWARDED_PROTO" => "https",
      "HTTP_X_FORWARDED_SSL" => "on",
      "HTTP_X_REAL_IP" => "198.51.100.77",
      "HTTP_CLIENT_IP" => "198.51.100.77",
      "HTTP_CF_CONNECTING_IP" => "198.51.100.77"
    }.merge(overrides)
  end
end
