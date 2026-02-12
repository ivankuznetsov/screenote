---
status: pending
priority: p1
issue_id: "003"
tags: [code-review, security, architecture]
dependencies: []
---

# Thread-Local MCP State Not Cleaned Up After Requests

## Problem Statement
`Thread.current[:mcp_current_project]` and `Thread.current[:mcp_current_api_key]` are set during MCP authentication but never cleared after request completion. In Puma's thread pool, stale values from a previous request could persist, creating a cross-tenant data leak risk if auth fails on a subsequent request.

## Findings
- `config/initializers/fast_mcp.rb:20-21`: Sets thread-locals but has no ensure/cleanup
- `app/tools/application_tool.rb:7,11`: Reads thread-locals
- Tests correctly clean up in teardown, production does not
- On auth failure (`return false` paths), thread-locals from previous request remain
- Agents: security-sentinel (H1), architecture-strategist, data-integrity-guardian, performance-oracle, pattern-recognition, dhh-rails-reviewer, agent-native-reviewer

## Proposed Solutions

### Option A: Migrate to ActiveSupport::CurrentAttributes (Recommended)
Create `Current.mcp_project` and `Current.mcp_api_key` using Rails' built-in mechanism that auto-resets per request.
- Pros: Idiomatic Rails, auto-cleanup, already used for web auth (`Current.user`)
- Cons: Need to verify FastMCP transport lifecycle triggers CurrentAttributes reset
- Effort: Small
- Risk: Low

### Option B: Add ensure block in transport
Wrap the token validation in an ensure block that clears Thread.current values.
- Pros: Minimal change
- Cons: Depends on FastMCP calling the right lifecycle hooks
- Effort: Small
- Risk: Low

## Technical Details
- Files: `config/initializers/fast_mcp.rb`, `app/tools/application_tool.rb`, `app/models/current.rb`

## Acceptance Criteria
- [ ] MCP context is cleared after every request (success or failure)
- [ ] No thread-local leakage between requests
- [ ] Tests verify cleanup on auth failure paths

## Work Log
- 2026-02-12: Created from code review findings (7 agents flagged this)
