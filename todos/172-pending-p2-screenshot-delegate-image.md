---
status: pending
priority: p2
issue_id: "172"
tags: [code-review, multi-viewport, pr-3, cleanup]
dependencies: []
---

# `delegate :image, to: :primary_image` on Screenshot; drop legacy attachment

## Problem Statement
Post-PR-2 views and tools chain `screenshot.primary_image&.image&.attached?` — a smelly abstraction leak. The cleaner Rails pattern is to delegate `image` through `primary_image` so callers write `screenshot.image.attached?` again. But Screenshot still has `has_one_attached :image` from the legacy column, which collides with a delegate macro.

## Findings
- **Source**: DHH Rails Reviewer P1 #2 on PR #29
- Blocked: can't add `delegate :image` while `has_one_attached :image` still exists on Screenshot

## Proposed Solution
During PR-3 (or a dedicated cleanup PR):
1. Remove `has_one_attached :image` and the legacy `image`, `width`, `height`, `status` columns from Screenshot (blobs already moved in PR-2 backfill).
2. Add on Screenshot:
   ```ruby
   has_one :primary_image, -> { order(Arel.sql("CASE viewport WHEN 0 THEN 0 ELSE viewport + 1 END")) },
     class_name: "ScreenshotImage"
   delegate :image, to: :primary_image, allow_nil: true
   ```
   (Rewriting `primary_image` from an instance method to a proper association so the delegate works.)
3. Simplify views back to `screenshot.image&.attached?`, `screenshot.image.variant(...)`.

## Acceptance Criteria
- [ ] Legacy `image`/`width`/`height`/`status` columns dropped from Screenshot
- [ ] `screenshot.image` returns the primary ScreenshotImage's image attachment via delegate
- [ ] All views updated to the shorter chain
