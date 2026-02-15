---
status: pending
priority: p3
issue_id: "052"
tags: [code-review, tests, flaky]
dependencies: []
---

# Improve screenshot image load assertion for CI reliability

## Problem Statement

`assert_screenshot_image_loaded` checks DOM presence of the image element but doesn't verify the image pixels are actually rendered. This could cause flaky tests in CI where image loading is slower.

## Findings

- Current assertion checks the element exists in DOM
- Doesn't verify `naturalWidth > 0` (image actually loaded)
- Annotorious drawing relies on actual pixel dimensions
- Could cause flaky annotation tests in CI environments

**Identified by:** Frontend Races Reviewer (Julik)

## Proposed Solutions

### Option 1: Add JS-based image load check

**Approach:** Use `evaluate_script` to check `image.complete && image.naturalWidth > 0`.

**Effort:** 30 minutes

**Risk:** Low

## Acceptance Criteria

- [ ] Image load assertion verifies actual pixel readiness
- [ ] Annotation tests don't flake on slow image loads

## Work Log

### 2026-02-12 - Initial Discovery

**By:** Claude Code (Frontend Races Reviewer)
