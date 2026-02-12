---
status: pending
priority: p2
issue_id: "010"
tags: [code-review, performance, agent-native]
dependencies: []
---

# Add Pagination to Controllers and MCP Tools

## Problem Statement
All list endpoints return unbounded result sets. As projects grow (especially with agent-initiated workflows), queries will load increasingly large datasets into memory.

## Findings
- `app/controllers/screenshots_controller.rb:8`: No limit/offset
- `app/tools/list_screenshots_tool.rb:12`: Returns all screenshots
- `app/tools/list_annotations_tool.rb:13`: Returns all annotations
- Agents: performance-oracle (OPT-5), architecture-strategist, agent-native-reviewer

## Proposed Solutions
Add optional `limit` and `offset` params with sensible defaults (e.g., 50).
- Effort: Medium | Risk: Low

## Acceptance Criteria
- [ ] MCP tools accept optional limit/offset parameters
- [ ] Web controllers paginate screenshot lists
- [ ] Default limit is reasonable (50)

## Work Log
- 2026-02-12: Created from code review (3 agents flagged this)
