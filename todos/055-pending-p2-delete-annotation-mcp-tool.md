---
status: pending
priority: p2
issue_id: "055"
tags: [code-review, agent-native, mcp]
dependencies: []
---

# Missing `delete_annotation` MCP Tool

## Problem Statement

The UI has a "Delete" button on every annotation, but no MCP tool exists for this. An agent that creates annotations via `create_annotation` cannot retract or correct them.

## Findings

- UI delete: `AnnotationsController#destroy` at `annotations/_annotation.html.erb` lines 32-36
- No corresponding MCP tool in `app/tools/`
- Agent-created annotations are permanent unless a human deletes them
- Source: Agent-native reviewer

## Proposed Solutions

### Option A: Add `DeleteAnnotationTool`
- **Effort**: Small (~20 lines)
- **Risk**: Low

## Acceptance Criteria

- [ ] Agent can delete an annotation via `delete_annotation` MCP tool
- [ ] Tool scoped to current project
- [ ] Returns structured error for not_found
- [ ] Test coverage added
