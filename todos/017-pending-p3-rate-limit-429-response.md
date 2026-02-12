---
status: pending
priority: p3
issue_id: "017"
tags: [code-review, agent-native, security]
dependencies: []
---

# Rate Limit Rejection Should Return 429, Not Silent Failure

## Problem Statement
When rate-limited, `valid_token?` returns false (same as invalid token). Agents can't distinguish "slow down" from "bad credentials," potentially causing them to abort the workflow entirely.

## Findings
- `config/initializers/fast_mcp.rb:25-29`: rate_limited? causes valid_token? to return false
- No HTTP 429 response or retry-after header
- Agents: agent-native-reviewer (Critical #4), security-sentinel (M3)

## Proposed Solutions
Return a distinct error code/message when rate-limited. May require FastMCP transport customization.
- Effort: Medium | Risk: Low

## Work Log
- 2026-02-12: Created from code review
