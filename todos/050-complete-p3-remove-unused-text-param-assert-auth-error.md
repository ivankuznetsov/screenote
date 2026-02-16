---
status: pending
priority: p3
issue_id: "050"
tags: [code-review, tests, yagni]
dependencies: []
---

# Remove unused text parameter from assert_auth_error

## Problem Statement

`assert_auth_error` in `auth_page.rb` accepts an optional `text` parameter but it's never called with one. YAGNI violation.

## Findings

- `test/system/pages/auth_page.rb:54-60` - method accepts `text = nil`
- Grep of all test files shows it's only ever called without arguments
- The branching adds unnecessary complexity

**Identified by:** Code Simplicity Reviewer

## Proposed Solutions

### Option 1: Simplify to no-argument version

**Approach:** Remove the text parameter and just assert presence.

**Effort:** 5 minutes

**Risk:** Low

## Acceptance Criteria

- [ ] assert_auth_error simplified to single-line assertion
- [ ] All tests still pass

## Work Log

### 2026-02-12 - Initial Discovery

**By:** Claude Code (Code Simplicity Reviewer)
