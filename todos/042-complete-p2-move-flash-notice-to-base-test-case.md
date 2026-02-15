---
status: pending
priority: p2
issue_id: "042"
tags: [code-review, tests, rails, architecture]
dependencies: []
---

# Move assert_flash_notice from AuthPage to ApplicationSystemTestCase

## Problem Statement

`assert_flash_notice` lives in `Pages::AuthPage` module but is used across all test files (auth, projects, screenshots). It's a cross-cutting concern that should be in the base test case.

## Findings

- `assert_flash_notice` defined in `test/system/pages/auth_page.rb:63-64`
- Flash notices appear on project pages, screenshot pages, and auth pages
- Tests that need flash assertions must include AuthPage even when not testing auth
- Same issue exists for `assert_flash_alert` if added later

**Identified by:** Kieran Rails Reviewer, Pattern Recognition Specialist

## Proposed Solutions

### Option 1: Move to ApplicationSystemTestCase (Recommended)

**Approach:** Move `assert_flash_notice` and the `FLASH_NOTICE`/`FLASH_ALERT` constants to `ApplicationSystemTestCase`.

**Effort:** 15 minutes

**Risk:** Low

## Technical Details

**Affected files:**
- `test/system/pages/auth_page.rb` - Remove flash methods
- `test/system/application_system_test_case.rb` - Add flash methods

## Acceptance Criteria

- [ ] assert_flash_notice available in all system tests without AuthPage
- [ ] All existing tests still pass

## Work Log

### 2026-02-12 - Initial Discovery

**By:** Claude Code (Kieran Rails Reviewer, Pattern Recognition)
