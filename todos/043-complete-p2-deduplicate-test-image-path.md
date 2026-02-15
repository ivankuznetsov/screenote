---
status: pending
priority: p2
issue_id: "043"
tags: [code-review, tests, dry]
dependencies: []
---

# Deduplicate TEST_IMAGE_PATH constant across test files

## Problem Statement

`TEST_IMAGE_PATH` is defined identically in two test files. If the fixture path changes, both must be updated.

## Findings

- `test/system/annotations_test.rb:16` defines `TEST_IMAGE_PATH = Rails.root.join("test/fixtures/files/test_screenshot.png")`
- `test/system/screenshots_test.rb:13` defines identical constant
- Both also share `navigate_to_demo_project` helper with identical logic

**Identified by:** Kieran Rails Reviewer, Pattern Recognition Specialist

## Proposed Solutions

### Option 1: Move to ApplicationSystemTestCase (Recommended)

**Approach:** Define `TEST_IMAGE_PATH` as a constant in `ApplicationSystemTestCase`.

**Effort:** 15 minutes

**Risk:** Low

## Technical Details

**Affected files:**
- `test/system/application_system_test_case.rb` - Add constant
- `test/system/annotations_test.rb` - Remove constant
- `test/system/screenshots_test.rb` - Remove constant

## Acceptance Criteria

- [ ] Single source of truth for test image path
- [ ] All tests still pass

## Work Log

### 2026-02-12 - Initial Discovery

**By:** Claude Code (Kieran Rails Reviewer, Pattern Recognition)
