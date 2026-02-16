---
status: complete
priority: p2
issue_id: "080"
tags: [code-review, security, race-condition, mcp]
dependencies: []
---

# Rate Limiting Race Condition (TOCTOU)

## Problem Statement
The `rate_limited?` method in `ProjectAuthTransport` has a TOCTOU (time-of-check-to-time-of-use) race condition. When `Rails.cache.increment` returns `nil` (cache miss), two concurrent requests can both enter the `if count.nil?` branch and each call `write(cache_key, 1, ...)`, effectively resetting the counter. Under high concurrency, an attacker could exceed the 60 requests/minute limit.

## Findings
- **Location**: `config/initializers/fast_mcp.rb` lines 46-56
- `increment` on a non-existent key may return `nil` on some cache backends
- The fallback `write` path is not atomic
- Two concurrent requests can both reset the counter to 1
- Found by security-sentinel

## Proposed Solutions

### Option 1: Atomic Write-If-Absent Pattern (Recommended)
- **Pros**: Eliminates race condition entirely
- **Cons**: Extra write call on every request
- **Effort**: Small
- **Risk**: Low

```ruby
def rate_limited?(api_key)
  cache_key = "mcp_rate_limit/#{api_key.id}"
  Rails.cache.write(cache_key, 0, expires_in: RATE_PERIOD, unless_exist: true)
  count = Rails.cache.increment(cache_key, 1)
  count > RATE_LIMIT
end
```

### Option 2: Use fetch + increment
- **Pros**: Clean pattern
- **Cons**: fetch block may have its own race window
- **Effort**: Small
- **Risk**: Low

## Recommended Action
Use `Rails.cache.write(cache_key, 0, expires_in: RATE_PERIOD, unless_exist: true)` before `increment` to ensure atomic initialization. Remove the `if count.nil?` fallback branch entirely.

## Technical Details
- **Affected Files**: `config/initializers/fast_mcp.rb`
- **Related Components**: MCP rate limiting, cache backend
- **Database Changes**: No

## Acceptance Criteria
- [ ] No race condition in rate limiting under concurrent requests
- [ ] Rate limit still enforced correctly (60 req/min)
- [ ] MCP E2E tests pass

## Work Log

### 2026-02-15 - Approved for Work
**By:** Claude Triage System
**Actions:**
- Issue approved during triage session
- Status changed from pending to ready

### 2026-02-15 - Identified in Code Review
**By:** security-sentinel agent (PR #10)

## Resources
- PR #10: Add MCP help page and dashboard banner
