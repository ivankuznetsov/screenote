---
status: pending
priority: p2
issue_id: "167"
tags: [code-review, ops, multi-viewport, pr-2]
dependencies: ["166"]
---

# Add reverse rake task `screenshots:rollback_backfill` for PR-2 deploy safety

## Problem Statement
PR-1 (#28) ships `rake screenshots:backfill_viewports` which moves Active Storage blobs from Screenshot → ScreenshotImage. Once run in prod, the blobs are gone from Screenshot. If PR-2 needs to be reverted post-deploy, `rails db:rollback` drops `screenshot_images` and orphans the blobs (polymorphic attachments have no FK, so cascade doesn't recover them). Result: visible-image data loss.

Ship a reverse task that detaches the blob from each ScreenshotImage, re-attaches it to the parent Screenshot, and destroys the ScreenshotImage. Document this as the pre-rollback procedure.

## Findings
- **Source**: Data Migration Expert + Data Integrity Guardian on PR #28
- **Location**: `lib/tasks/screenshots.rake` — currently only the forward task

## Proposed Solution
```ruby
# lib/tasks/screenshots.rake
desc "Move ScreenshotImage(:desktop) blobs back onto their Screenshot. APPLY=1 commits."
task rollback_backfill: :environment do
  # Mirror of backfill_viewports but in reverse: for each ScreenshotImage(:desktop)
  # with an attached image whose Screenshot does NOT have an image, move the
  # blob back.
end
```

## Acceptance Criteria
- [ ] Task mirrors forward task's dry-run / APPLY semantics + idempotency
- [ ] Test coverage: dry-run no-op, apply restores blob to Screenshot, idempotent re-run, leaves untouched rows alone
- [ ] Task landed before or with PR-2 so operators have a tested rollback path before PR-2's deploy
