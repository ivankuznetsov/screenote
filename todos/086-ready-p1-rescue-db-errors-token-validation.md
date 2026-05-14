---
status: ready
priority: p1
issue_id: "086"
tags: [code-review, reliability, oauth]
dependencies: []
---

# No Rescue Around Database Queries in Token Validation

## Problem Statement
`validate_oauth_token` and `validate_api_key` call `Doorkeeper::AccessToken.by_token()`, `Project.find_by()`, and `ApiKey.active.find_by_token()` with no rescue block. If the database is temporarily unavailable, these raise unhandled exceptions that produce raw 500 errors instead of proper JSON-RPC 401 responses. The `call` method only rescues `RateLimitedError`. Additionally, `api_key.touch_last_used!` can crash a successful auth request if the DB write fails.

## Findings
- `config/initializers/fast_mcp.rb` lines 39-47: `valid_token?` has no rescue
- `config/initializers/fast_mcp.rb` lines 61-72: DB queries without error handling
- `config/initializers/fast_mcp.rb` line 57: `touch_last_used!` can crash on write failure
- `config/initializers/fast_mcp.rb` lines 74-79: `rate_limited?` cache failure crashes auth
- Agent: silent-failure-hunter (HIGH #2, #3; MEDIUM #8)

## Proposed Solutions

### Option A: Rescue in valid_token? with graceful degradation (Recommended)
```ruby
def valid_token?(token)
  return false if token.blank?
  if token.start_with?("sk_proj_")
    validate_api_key(token)
  else
    validate_oauth_token(token)
  end
rescue RateLimitedError
  raise
rescue StandardError => e
  Rails.logger.error("Token validation error: #{e.class}: #{e.message}")
  Honeybadger.notify(e, context: { token_prefix: token&.first(8) })
  false
end
```
Also wrap `touch_last_used!` and `rate_limited?` in their own rescues.
- Pros: DB failures produce proper 401 instead of 500; Honeybadger notified
- Cons: May mask unexpected errors (mitigated by Honeybadger)
- Effort: Small
- Risk: Low

## Recommended Action
Option A

## Technical Details
- Affected files: `config/initializers/fast_mcp.rb`

## Acceptance Criteria
- [ ] DB connection failure during token validation returns 401, not 500
- [ ] `touch_last_used!` failure does not crash the request
- [ ] `rate_limited?` cache failure allows the request through (fail open)
- [ ] All errors reported to Honeybadger

## Work Log
- 2026-02-16: Created from OAuth 2.1 code review
- 2026-02-16: Approved during triage — Status: pending → ready

## Resources
- FastMcp transport: `fast-mcp-1.6.0/lib/mcp/transports/authenticated_rack_transport.rb`
