---
status: pending
priority: p2
issue_id: "044"
tags: [code-review, tests, dry]
dependencies: []
---

# Deduplicate navigate_to_demo_project helper across test files

## Problem Statement

`navigate_to_demo_project` is defined identically in `screenshots_test.rb` and `annotations_test.rb`. Same navigation logic duplicated.

## Findings

- Both files define a private method that logs in and navigates to the demo project
- Logic is identical: login_as_test_user → visit projects → click project card

**Identified by:** Pattern Recognition Specialist

## Proposed Solutions

### Option 1: Move to ApplicationSystemTestCase (Recommended)

**Approach:** Extract shared navigation helper to base test case.

**Effort:** 15 minutes

**Risk:** Low

## Technical Details

**Affected files:**
- `test/system/application_system_test_case.rb` - Add helper
- `test/system/annotations_test.rb` - Remove helper
- `test/system/screenshots_test.rb` - Remove helper

## Acceptance Criteria

- [ ] Single definition of navigate_to_demo_project
- [ ] All tests still pass

## Work Log

### 2026-02-12 - Initial Discovery

**By:** Claude Code (Pattern Recognition)
