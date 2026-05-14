---
status: ready
priority: p2
issue_id: "097"
tags: [code-review, reliability, oauth]
dependencies: []
---

# Middleware Swap Failure Silently Breaks MCP

## Problem Statement
If the FastMcp middleware swap fails (gem upgrade changes transport class name), MCP runs with default authentication that rejects all real tokens. Only a `warn` log is emitted — no Honeybadger alert for what is effectively a total MCP outage.

## Findings
- `config/initializers/fast_mcp.rb` lines 137-143: `rescue RuntimeError` with `warn` log only
- Agent: silent-failure-hunter (MEDIUM #7), architecture-strategist

## Proposed Solutions

### Option A: Upgrade to error + Honeybadger (Recommended)
```ruby
rescue RuntimeError => e
  if e.message.include?("No such middleware")
    Rails.logger.error("CRITICAL: FastMcp ProjectAuthTransport middleware swap failed")
    Honeybadger.notify("FastMcp middleware swap failed - MCP auth broken")
  else
    raise
  end
end
```
Also consider a boot-time assertion to verify the swap succeeded.
- Effort: Small
- Risk: Low

## Technical Details
- Affected files: `config/initializers/fast_mcp.rb`

## Acceptance Criteria
- [ ] Middleware swap failure reported to Honeybadger
- [ ] Log level is `error`, not `warn`

## Work Log
- 2026-02-16: Created from OAuth 2.1 code review
- 2026-02-16: Approved during triage — Status: pending → ready
