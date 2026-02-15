---
status: pending
priority: p3
issue_id: "048"
tags: [code-review, tests, data-testid, coverage]
dependencies: []
---

# Add data-testid and E2E coverage for API keys views

## Problem Statement

API keys views have zero `data-testid` attributes and zero E2E test coverage. While out of scope for the current PR, this is an important gap for agent-native accessibility.

## Findings

- No data-testid on API key management views
- No system tests for API key CRUD operations
- API keys are critical for MCP agent access (core product feature)

**Identified by:** Agent-Native Reviewer

## Proposed Solutions

### Option 1: Add in follow-up PR

**Approach:** Create separate PR adding data-testid to API views and E2E tests for key management.

**Effort:** 2-3 hours

**Risk:** Low

## Acceptance Criteria

- [ ] API key views have data-testid attributes
- [ ] E2E tests cover API key CRUD
- [ ] Tests pass

## Work Log

### 2026-02-12 - Initial Discovery

**By:** Claude Code (Agent-Native Reviewer)
