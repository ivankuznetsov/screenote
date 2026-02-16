---
status: pending
priority: p3
issue_id: "051"
tags: [code-review, tests, documentation]
dependencies: []
---

# Document wait_for_timeout(200) Annotorious constraint in tests

## Problem Statement

`wait_for_timeout(200)` is used in annotation tests between drawing clicks but lacks a comment explaining why. Multiple reviewers flagged it as suspicious.

## Findings

- Annotorious click-click drawing mode needs a minimum pause between first and second click
- Without the pause, the second click is interpreted as a double-click or ignored
- This is documented in project MEMORY.md but not in the test code itself

**Identified by:** Multiple reviewers

## Proposed Solutions

### Option 1: Add inline comment (Recommended)

**Approach:** Add a comment above each `wait_for_timeout(200)` explaining the Annotorious constraint.

**Effort:** 5 minutes

**Risk:** Low

## Acceptance Criteria

- [ ] Each wait_for_timeout has explanatory comment
- [ ] Comment references Annotorious click-click drawing mode

## Work Log

### 2026-02-12 - Initial Discovery

**By:** Claude Code (Multiple reviewers)
