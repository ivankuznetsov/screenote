---
status: pending
priority: p1
issue_id: "002"
tags: [code-review, agent-native]
dependencies: []
---

# No Structured Error Handling in MCP Tools

## Problem Statement
All 5 MCP tools let ActiveRecord exceptions (RecordNotFound, RecordInvalid) propagate raw. Agents receive unpredictable error formats, making it impossible to distinguish "not found" from "validation failed" from "rate limited." This breaks the agent-initiated feedback loop.

## Findings
- All files in `app/tools/`: No rescue blocks, no structured JSON error responses
- Rate limit rejection in `fast_mcp.rb` returns false (same as invalid token) - agent can't tell the difference
- `GetAnnotationTool` returns null cropped_image without explaining why (pending vs failed screenshot)
- Agents: agent-native-reviewer (Critical #3, #4), architecture-strategist

## Proposed Solutions

### Option A: Error handling in ApplicationTool base class (Recommended)
Add a `call_with_error_handling` wrapper or rescue blocks in ApplicationTool that catches common exceptions and returns structured JSON: `{ error: "not_found", message: "..." }`.
- Pros: DRY, consistent error format across all tools
- Cons: Need to understand FastMCP error propagation
- Effort: Small
- Risk: Low

## Technical Details
- Files: `app/tools/application_tool.rb`, all tool files

## Acceptance Criteria
- [ ] RecordNotFound returns `{ error: "not_found", message: "..." }`
- [ ] RecordInvalid returns `{ error: "validation_failed", details: [...] }`
- [ ] GetAnnotationTool includes screenshot_status in response
- [ ] Tests verify structured error responses

## Work Log
- 2026-02-12: Created from code review findings (agent-native-reviewer)
