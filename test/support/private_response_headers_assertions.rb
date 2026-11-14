# frozen_string_literal: true

module PrivateResponseHeadersAssertions
  def assert_private_headers
    assert_includes response.headers.fetch("Cache-Control"), "no-store"
    assert_equal "no-cache", response.headers["Pragma"]
    assert_equal "no-referrer", response.headers["Referrer-Policy"]
    assert_equal "noindex, nofollow", response.headers["X-Robots-Tag"]
  end
end
