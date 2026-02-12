# frozen_string_literal: true

Rack::Attack.cache.store = Rails.cache

# Throttle MCP endpoints by API key token
# 60 requests per minute per API key
Rack::Attack.throttle("mcp/api_key", limit: 60, period: 1.minute) do |request|
  if request.path.start_with?("/mcp")
    # Extract Bearer token from Authorization header
    auth = request.env["HTTP_AUTHORIZATION"]
    auth&.sub(/\ABearer\s+/i, "")
  end
end

# Throttle MCP endpoints by IP as a fallback (for unauthenticated requests)
# 10 requests per minute per IP
Rack::Attack.throttle("mcp/ip", limit: 10, period: 1.minute) do |request|
  request.ip if request.path.start_with?("/mcp")
end

# Return 429 with JSON body for MCP rate limiting
Rack::Attack.throttled_responder = lambda do |request|
  if request.path.start_with?("/mcp")
    [ 429, { "Content-Type" => "application/json" }, [ { error: "Rate limit exceeded. Try again later." }.to_json ] ]
  else
    [ 429, { "Content-Type" => "text/plain" }, [ "Rate limit exceeded. Try again later.\n" ] ]
  end
end
