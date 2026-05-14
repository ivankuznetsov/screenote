---
status: ready
priority: p2
issue_id: "096"
tags: [code-review, reliability]
dependencies: ["086"]
---

# rate_limited? Cache Failure Crashes Authentication

## Problem Statement
`rate_limited?` uses `Rails.cache.increment` which can return nil on cache failure. The comparison `nil > RATE_LIMIT` raises `ArgumentError`. A cache failure should not break authentication — it should degrade gracefully (fail open).

## Findings
- `config/initializers/fast_mcp.rb` lines 74-79
- Agent: silent-failure-hunter (MEDIUM #8)

## Proposed Solutions

### Option A: Nil-safe comparison + rescue (Recommended)
```ruby
def rate_limited?(api_key)
  cache_key = "mcp_rate_limit/#{api_key.id}"
  Rails.cache.write(cache_key, 0, expires_in: RATE_PERIOD, unless_exist: true)
  count = Rails.cache.increment(cache_key, 1)
  count.present? && count > RATE_LIMIT
rescue StandardError => e
  Rails.logger.error("Rate limiting check failed: #{e.class}: #{e.message}")
  Honeybadger.notify(e, context: { api_key_id: api_key.id })
  false
end
```
- Effort: Small
- Risk: Low

## Technical Details
- Affected files: `config/initializers/fast_mcp.rb`

## Acceptance Criteria
- [ ] Cache failure allows requests through (fail open)
- [ ] Error logged and reported to Honeybadger

## Work Log
- 2026-02-16: Created from OAuth 2.1 code review
- 2026-02-16: Approved during triage — Status: pending → ready
