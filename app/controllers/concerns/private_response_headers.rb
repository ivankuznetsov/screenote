# frozen_string_literal: true

# Responses that carry credentials, one-time links, or account administration
# must never be cached, leak through the Referer header, or be indexed.
module PrivateResponseHeaders
  extend ActiveSupport::Concern

  private

  def set_private_headers
    response.set_header("Cache-Control", "no-store, max-age=0")
    response.set_header("Pragma", "no-cache")
    response.set_header("Referrer-Policy", "no-referrer")
    response.set_header("X-Robots-Tag", "noindex, nofollow")
  end
end
