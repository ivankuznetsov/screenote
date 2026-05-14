---
status: pending
priority: p3
issue_id: "169"
tags: [code-review, rails, consistency]
dependencies: []
---

# Add `prefix: :status` to Screenshot status enum for consistency

## Problem Statement
`ScreenshotImage` declares `enum :status, {...}, prefix: :status` (yielding `status_pending?`, `status_ready?`). `Screenshot` declares the same enum without a prefix, so it generates `pending?`, `ready?`. In joined contexts (e.g. `Screenshot.joins(:screenshot_images)`) the predicate names collide or create ambiguous method resolution.

Kieran review of PR #28 flagged this as consistency debt.

## Findings
- **Source**: Kieran Rails Reviewer P3 finding on PR #28
- **Location**: `app/models/screenshot.rb:12`

## Acceptance Criteria
- [ ] `Screenshot`'s status enum declared with `prefix: :status`
- [ ] Update all callers of `screenshot.pending?`, `screenshot.ready?`, `screenshot.failed?` to prefixed forms
- [ ] Tests pass
