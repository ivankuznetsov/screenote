---
status: pending
priority: p3
issue_id: "049"
tags: [code-review, data-testid]
dependencies: []
---

# Add data-testid to action buttons (Delete, Resolve, Save)

## Problem Statement

Action buttons (Delete project/screenshot, Resolve annotation, Save) lack `data-testid` attributes, making them harder to target in E2E tests and by AI agents.

## Findings

- Delete buttons on projects and screenshots lack testid
- Resolve button on annotations lacks testid
- Currently targeted via semantic selectors (input[type=submit]) which works but is less explicit

**Identified by:** Agent-Native Reviewer

## Proposed Solutions

### Option 1: Add data-testid to action buttons

**Effort:** 30 minutes

**Risk:** Low

## Acceptance Criteria

- [ ] All CRUD action buttons have data-testid
- [ ] E2E tests updated to use new testids where beneficial

## Work Log

### 2026-02-12 - Initial Discovery

**By:** Claude Code (Agent-Native Reviewer)
