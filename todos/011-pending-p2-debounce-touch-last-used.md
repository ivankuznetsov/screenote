---
status: pending
priority: p2
issue_id: "011"
tags: [code-review, performance]
dependencies: []
---

# Debounce touch_last_used! on Every MCP Request

## Problem Statement
Every MCP request triggers a synchronous `UPDATE api_keys SET last_used_at = ...` write. During rapid agent sessions, this causes unnecessary write amplification, lock contention, and latency.

## Findings
- `config/initializers/fast_mcp.rb:19`: `api_key.touch_last_used!` on every request
- `app/models/api_key.rb:30-32`: `update_column(:last_used_at, Time.current)`
- Agents: performance-oracle (CRITICAL-4)

## Proposed Solutions
Add time-based guard: only update if last update was >5 minutes ago.
```ruby
def touch_last_used!
  return if last_used_at.present? && last_used_at > 5.minutes.ago
  update_column(:last_used_at, Time.current)
end
```
- Effort: Small | Risk: Low

## Acceptance Criteria
- [ ] touch_last_used! skips update if updated within last 5 minutes
- [ ] Tests verify debounce behavior

## Work Log
- 2026-02-12: Created from code review (performance-oracle)
