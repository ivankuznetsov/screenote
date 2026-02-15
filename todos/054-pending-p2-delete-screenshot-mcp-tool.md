---
status: pending
priority: p2
issue_id: "054"
tags: [code-review, agent-native, mcp]
dependencies: []
---

# Missing `delete_screenshot` MCP Tool

## Problem Statement

The UI has a "Delete" button on every screenshot, but no MCP tool exists for this. Agents that upload screenshots during iterative development loops cannot clean up after themselves, causing stale screenshots to accumulate.

## Findings

- UI delete: `ScreenshotsController#destroy` at `screenshots/show.html.erb` line 12-14
- No corresponding MCP tool in `app/tools/`
- The "agent-initiated" workflow (CLAUDE.md) describes an iterative loop where screenshots accumulate
- Source: Agent-native reviewer

## Proposed Solutions

### Option A: Add `DeleteScreenshotTool`
- **Pros**: Direct parity with UI, simple
- **Effort**: Small (~20 lines following existing tool patterns)
- **Risk**: Low

## Acceptance Criteria

- [ ] Agent can delete a screenshot it uploaded via `delete_screenshot` MCP tool
- [ ] Tool scoped to current project (cannot delete other projects' screenshots)
- [ ] Returns structured error for not_found
- [ ] Test coverage added
