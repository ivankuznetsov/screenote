---
status: ready
priority: p2
issue_id: "088"
tags: [code-review, security, oauth]
dependencies: []
---

# No Rate Limiting on OAuth-Authenticated MCP Requests

## Problem Statement
API key authentication has rate limiting (60 req/min), but OAuth token authentication bypasses it entirely. An agent with an OAuth token can make unlimited MCP requests.

## Findings
- `config/initializers/fast_mcp.rb` lines 49-58: `validate_api_key` calls `rate_limited?`
- `config/initializers/fast_mcp.rb` lines 61-72: `validate_oauth_token` has no rate limiting
- Agents: security-sentinel (H4), architecture-strategist

## Proposed Solutions

### Option A: Extend rate limiting to OAuth tokens (Recommended)
Key the rate limit on access token ID or `(application_id, resource_owner_id)` pair:
```ruby
def validate_oauth_token(token)
  # ... existing validation ...
  raise RateLimitedError if rate_limited_oauth?(access_token)
  # ...
end

def rate_limited_oauth?(access_token)
  cache_key = "mcp_rate_limit/oauth/#{access_token.id}"
  Rails.cache.write(cache_key, 0, expires_in: RATE_PERIOD, unless_exist: true)
  count = Rails.cache.increment(cache_key, 1)
  count.present? && count > RATE_LIMIT
end
```
- Pros: Consistent behavior regardless of auth method
- Cons: Slightly more code
- Effort: Small
- Risk: Low

## Technical Details
- Affected files: `config/initializers/fast_mcp.rb`

## Acceptance Criteria
- [ ] OAuth-authenticated requests rate limited at same threshold as API keys
- [ ] Rate limit key differs from API key rate limit
- [ ] 429 response returned when exceeded

## Work Log
- 2026-02-16: Created from OAuth 2.1 code review
- 2026-02-16: Approved during triage — Status: pending → ready
