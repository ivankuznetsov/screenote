---
status: complete
priority: p2
issue_id: "081"
tags: [code-review, security, information-disclosure, mcp]
dependencies: []
---

# FastMcp Internal Error Leaks Exception Messages

## Problem Statement
The upstream FastMcp gem's `handle_internal_error` method leaks raw `error.message` into the HTTP response body via `json_rpc_error_response(500, -32603, "Internal error: #{error.message}")`. While `ApplicationTool#with_error_handling` properly sanitizes errors within tool execution, errors that occur before reaching the tool's `call` method (e.g., during JSON-RPC routing or argument deserialization) would expose internal details like database schema info, file paths, or stack context.

## Findings
- **Location**: FastMcp gem `lib/mcp/transports/rack_transport.rb` lines 566-568
- `ApplicationTool#with_error_handling` already sanitizes in-tool errors correctly
- Pre-tool errors (malformed JSON-RPC, routing errors) bypass this protection
- Found by security-sentinel

## Proposed Solutions

### Option 1: Override handle_internal_error in ProjectAuthTransport (Recommended)
- **Pros**: Sanitizes all error output, sends to Honeybadger
- **Cons**: Overriding another internal method
- **Effort**: Small
- **Risk**: Low

```ruby
def handle_internal_error(error)
  @logger.error("Error processing message: #{error.message}")
  Honeybadger.notify(error)
  json_rpc_error_response(500, -32_603, "Internal error")
end
```

## Recommended Action
Override `handle_internal_error` in `ProjectAuthTransport` to return a generic "Internal error" message while logging the real error and notifying Honeybadger.

## Technical Details
- **Affected Files**: `config/initializers/fast_mcp.rb`
- **Related Components**: FastMcp gem internals, error handling
- **Database Changes**: No

## Acceptance Criteria
- [ ] No raw error messages exposed in MCP HTTP responses
- [ ] Errors still logged and sent to Honeybadger
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
