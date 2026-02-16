---
status: complete
priority: p2
issue_id: "071"
tags: [code-review, performance, mcp]
dependencies: []
---

# send_message Override Causes Double JSON Serialization

## Problem Statement
The `send_message` override in `ProjectAuthTransport` calls `super` (which already serializes and sends the message), then re-serializes the message object into JSON a second time for the Rack response body. This is wasteful and could cause inconsistencies if `super` modifies the message.

## Findings
- **Location**: `config/initializers/fast_mcp.rb` lines 24-28
- `super` handles SSE broadcast (serializes JSON internally)
- Then `JSON.generate(message)` serializes again for the HTTP response body
- Performance impact: double serialization on every MCP response
- Found by performance-oracle, code-simplicity-reviewer

## Proposed Solutions

### Option 1: Cache the JSON String (Recommended)
- **Pros**: Single serialization, clear intent
- **Cons**: Minor refactor
- **Effort**: Small
- **Risk**: Low

```ruby
def send_message(message)
  json = message.is_a?(String) ? message : JSON.generate(message)
  super(json)
  [json]
end
```

### Option 2: Skip super and Handle Directly
- **Pros**: No double work
- **Cons**: May break SSE broadcast if super does more than serialize
- **Effort**: Small
- **Risk**: Medium

## Recommended Action
Serialize JSON once before calling `super`, then reuse the string for the response body. Simple reorder of existing code.

## Technical Details
- **Affected Files**: `config/initializers/fast_mcp.rb`
- **Related Components**: FastMcp transport, MCP message handling
- **Database Changes**: No

## Acceptance Criteria
- [ ] JSON serialization happens only once per message
- [ ] SSE broadcast still works correctly
- [ ] MCP E2E tests pass
- [ ] No regression in response format

## Work Log

### 2026-02-15 - Approved for Work
**By:** Claude Triage System
**Actions:**
- Issue approved during triage session
- Status changed from pending to ready

### 2026-02-15 - Identified in Code Review
**By:** Multi-agent review (PR #10)
**Actions:**
- Found by performance-oracle and code-simplicity-reviewer

## Resources
- PR #10: Add MCP help page and dashboard banner
