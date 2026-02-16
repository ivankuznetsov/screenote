---
status: pending
priority: p2
issue_id: "046"
tags: [code-review, tests, quality]
dependencies: []
---

# Remove meaningless body assertion in visit_projects

## Problem Statement

`visit_projects` in `projects_page.rb` asserts `"body"` selector which always exists on any HTML page, making the wait meaningless.

## Findings

- `test/system/pages/projects_page.rb:20` - `assert_selector "body"` after visiting `/projects`
- Should wait for actual page content like `[data-testid="page-title"]` or `[data-testid="project-list"]`

**Identified by:** Kieran Rails Reviewer, Code Simplicity Reviewer

## Proposed Solutions

### Option 1: Wait for meaningful selector (Recommended)

**Approach:** Replace `assert_selector "body"` with `assert_selector '[data-testid="page-title"], [data-testid="empty-state"]'`.

**Effort:** 5 minutes

**Risk:** Low

## Technical Details

**Affected files:**
- `test/system/pages/projects_page.rb:20`

## Acceptance Criteria

- [ ] visit_projects waits for meaningful page content
- [ ] All tests still pass

## Work Log

### 2026-02-12 - Initial Discovery

**By:** Claude Code (Kieran Rails Reviewer, Code Simplicity)
