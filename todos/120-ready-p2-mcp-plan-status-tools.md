---
status: ready
priority: p2
issue_id: "120"
tags: [code-review, mcp, agent-native, billing, pr-11]
dependencies: []
---

# No Agent-Facing MCP Tools for Plan Status or Limits

## Problem Statement
Screenote is a "SaaS visual feedback tool for AI agents," yet the entire billing feature is implemented as a user-facing web UI concern with zero agent-facing surface area. There are no MCP tools for checking subscription status, plan limits, or remaining capacity. Agents operating via MCP are blind to plan constraints and will receive no actionable guidance when limits are hit.

## Findings
- **Files**: `app/tools/` — no subscription-related tool exists
- Identified by: Agent Native Reviewer (CRITICAL)
- 0/5 billing-related capabilities are agent-accessible
- 6/6 core screenshot/annotation capabilities are agent-accessible (existing)
- No plan context in `list_screenshots` or `list_annotations` responses
- No dynamic context injection in MCP server config

## Proposed Solutions

### Option A: Add `get_project_info` MCP tool (Recommended)
Returns project metadata, owner plan, and applicable limits:
```json
{
  "project": { "name": "My Project" },
  "plan": "free",
  "limits": {
    "projects": { "used": 1, "max": 1 },
    "members_per_project": { "used": 0, "max": 1 }
  }
}
```
- **Pros**: Gives agents context parity with UI
- **Cons**: Adds a new tool
- **Effort**: Medium
- **Risk**: Low

### Option B: Include plan context in existing tool responses
Add `project.plan` field to `list_screenshots` and `list_annotations` responses.
- **Pros**: Passive context injection, no new tool
- **Cons**: Doesn't provide limits or capacity info
- **Effort**: Small
- **Risk**: Low

## Acceptance Criteria
- [ ] Agent can discover current plan via MCP
- [ ] Agent can check capacity/limits via MCP
- [ ] Plan-limit errors return structured, actionable error responses

## Work Log
- 2026-02-16: Created from PR #11 agent-native review
