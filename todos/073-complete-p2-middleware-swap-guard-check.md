---
status: complete
priority: p2
issue_id: "073"
tags: [code-review, rails, middleware, resilience]
dependencies: []
---

# middleware.swap Will Crash if Target Middleware Absent

## Problem Statement
`Rails.application.config.middleware.swap(FastMcp::Transports::AuthenticatedRackTransport, ...)` will raise an error if the target middleware is not in the stack (e.g., if FastMcp changes its internals in a gem update). There's no guard check, so a gem update could crash the entire application on boot.

## Findings
- **Location**: `config/initializers/fast_mcp.rb` lines 81-93
- `middleware.swap` raises `RuntimeError` if the middleware class is not found in the stack
- This is fragile coupling to FastMcp internals
- Found by architecture-strategist, security-sentinel

## Proposed Solutions

### Option 1: Add Guard Check Before Swap (Recommended)
- **Pros**: Graceful degradation, clear error message
- **Cons**: Slightly more code
- **Effort**: Small
- **Risk**: Low

```ruby
if Rails.application.config.middleware.include?(FastMcp::Transports::AuthenticatedRackTransport)
  Rails.application.config.middleware.swap(...)
else
  Rails.logger.warn "FastMcp AuthenticatedRackTransport not found in middleware stack"
end
```

### Option 2: Pin FastMcp Version
- **Pros**: Prevents unexpected changes
- **Cons**: Doesn't fix the underlying fragility
- **Effort**: Small
- **Risk**: Low

## Recommended Action
Wrap `middleware.swap` in an `if middleware.include?()` check. Log a warning if the target is missing so developers know to investigate.

## Technical Details
- **Affected Files**: `config/initializers/fast_mcp.rb`
- **Related Components**: Rails middleware stack, FastMcp gem
- **Database Changes**: No

## Acceptance Criteria
- [ ] Application boots gracefully even if middleware class changes
- [ ] Warning logged when swap target not found
- [ ] MCP E2E tests pass

## Work Log

### 2026-02-15 - Approved for Work
**By:** Claude Triage System
**Actions:**
- Issue approved during triage session
- Status changed from pending to ready

### 2026-02-15 - Identified in Code Review
**By:** Multi-agent review (PR #10)
**Actions:**
- Found by architecture-strategist, security-sentinel

## Resources
- PR #10: Add MCP help page and dashboard banner
